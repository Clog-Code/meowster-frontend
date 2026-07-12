import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../data/services/agent_stream_client.dart';
import '../../../data/services/location_service.dart';
import '../../../data/services/pet_streak_client.dart';
import '../../../data/services/speech_to_text_service.dart';
import '../../../data/services/text_to_speech_service.dart';
import '../../../data/services/visual_llm_client.dart';
import '../../../domain/models/pet_capture_result.dart';
import '../../core/pet_theme.dart';
import '../capture/capture_screen.dart';
import 'chat_composer.dart';

class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({
    required this.client,
    this.initialCapture,
    this.streakClient = const EmptyPetStreakClient(),
    this.visualLlmClient = const DisabledVisualLlmClient(),
    this.locationService = const GeolocatorLocationService(),
    this.speechToTextService,
    this.textToSpeechService,
    this.autoReadPreferenceStore,
    super.key,
  });

  final AgentStreamClient client;
  final PetCaptureResult? initialCapture;
  final PetStreakClient streakClient;
  final VisualLlmClient visualLlmClient;
  final LocationService locationService;
  final SpeechToTextService? speechToTextService;
  final TextToSpeechService? textToSpeechService;
  final AutoReadPreferenceStore? autoReadPreferenceStore;

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  final _messages = <ChatMessage>[];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _threadId = newAgentId();
  ChatMessage? _currentAssistant;
  bool _isSending = false;
  bool _isLocating = false;
  PetAgentLocation? _sharedLocation;
  bool _sendLocationWithNextReply = false;
  int _activeRunToken = 0;
  late final SpeechToTextService _speechToTextService;
  late final TextToSpeechService _textToSpeechService;
  late final AutoReadPreferenceStore _autoReadPreferenceStore;
  late final Future<void> _autoReadReady;
  late final bool _ownsTextToSpeechService;
  bool _isListening = false;
  bool _isDictationHeld = false;
  bool _isDisposed = false;
  bool _autoReadEnabled = true;
  double _soundLevel = 0;
  int _speechPlaybackToken = 0;
  String? _speakingMessageId;
  String _dictationBaseText = '';
  final _autoReadMessageIds = <String>{};

  @override
  void initState() {
    super.initState();
    _speechToTextService =
        widget.speechToTextService ?? NativeSpeechToTextService();
    _ownsTextToSpeechService = widget.textToSpeechService == null;
    _textToSpeechService =
        widget.textToSpeechService ??
        KokoroTextToSpeechService.fromEnvironment();
    _autoReadPreferenceStore =
        widget.autoReadPreferenceStore ?? SharedPreferencesAutoReadStore();
    _autoReadReady = _loadAutoReadPreference();
    final capture = widget.initialCapture;
    if (capture != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendPerception(capture);
      });
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_speechToTextService.cancel());
    if (_ownsTextToSpeechService) {
      unawaited(_textToSpeechService.dispose());
    } else {
      unawaited(_textToSpeechService.stop());
    }
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAutoReadPreference() async {
    var enabled = true;
    try {
      enabled = await _autoReadPreferenceStore.readEnabled();
    } on Object catch (error) {
      debugPrint('Could not load auto-read preference: $error');
    }
    if (!mounted || _isDisposed) return;
    setState(() => _autoReadEnabled = enabled);
  }

  Future<void> _sendPerception(PetCaptureResult capture) async {
    if (_isSending) return;
    final payload = capture.toPerceptionPayload(_threadId);
    final userMessage = ChatMessage(
      id: _newId(),
      role: ChatRole.user,
      content: capture.userDescription,
      attachmentLabel: capture.attachmentLabel,
      capture: capture,
    );

    setState(() {
      _messages.add(userMessage);
      _isSending = true;
    });
    _scrollToBottom();
    await _consume(path: '/perception', payload: payload);
  }

  Future<void> _sendChat(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isSending) return;
    await _stopSpeechPlayback();
    if (!mounted) return;
    final agentContext = _sendLocationWithNextReply
        ? _locationContextMessage(_sharedLocation)
        : null;

    _inputController.clear();
    setState(() {
      _messages.add(
        ChatMessage(
          id: _newId(),
          role: ChatRole.user,
          content: trimmed,
          agentContext: agentContext,
        ),
      );
      _sendLocationWithNextReply = false;
      _isSending = true;
    });
    _scrollToBottom();

    final payload = buildRunAgentInput(
      threadId: _threadId,
      runId: _newId(),
      messages: _messages,
      context: _buildAgentContext(),
    );
    await _consume(path: '/agent', payload: payload);
  }

  Future<void> _consume({
    required String path,
    required Map<String, dynamic> payload,
  }) async {
    final runToken = ++_activeRunToken;
    var endedCleanly = false;
    try {
      await widget.client.streamAgent(
        path: path,
        payload: payload,
        onEvent: (event) {
          if (runToken != _activeRunToken) return;
          if (event.type == 'TEXT_MESSAGE_END' ||
              event.type == 'RUN_FINISHED') {
            endedCleanly = true;
          }
          _applyEvent(event);
        },
      );
    } on Object catch (error, stackTrace) {
      if (runToken != _activeRunToken) return;
      if (!mounted) return;
      debugPrint('Agent stream error: $error');
      debugPrintStack(stackTrace: stackTrace);
      setState(() {
        if (_currentAssistant != null) _messages.remove(_currentAssistant);
        _currentAssistant = null;
        _isSending = false;
        _messages.add(
          ChatMessage(
            id: _newId(),
            role: ChatRole.system,
            content: 'Connection issue: ${_friendlyError(error)}',
            isError: true,
          ),
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      return;
    }

    if (runToken != _activeRunToken) return;
    if (!mounted) return;
    final finishedAssistant = _currentAssistant;
    setState(() {
      _currentAssistant?.isStreaming = false;
      if (!endedCleanly &&
          _currentAssistant != null &&
          _currentAssistant!.content.isEmpty) {
        _messages.remove(_currentAssistant);
      }
      _currentAssistant = null;
      _isSending = false;
    });
    if (endedCleanly && finishedAssistant?.content.trim().isNotEmpty == true) {
      unawaited(_autoReadAssistant(finishedAssistant!));
    }
  }

  List<Map<String, dynamic>> _buildAgentContext() {
    return [
      {
        'description': 'Mock pet profile for the current pet.',
        'value': jsonEncode(
          const PetCaptureResult(
            kind: CaptureMediaKind.demo,
            species: 'cat',
            emotion: 'watchful',
            healthFlags: ['needs review'],
            sourceLabel: 'Mock profile',
          ).mockPetProfile,
        ),
      },
      if (_sharedLocation != null)
        {
          'description':
              'Approximate device location shared by the user for nearby recommendations.',
          'value': jsonEncode(_sharedLocation!.toJson()),
        },
    ];
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('Connection refused')) {
      return 'Backend is not reachable. Check AGENT_BASE_URL and that uvicorn is running.';
    }
    if (text.contains('Cleartext') || text.contains('CLEARTEXT')) {
      return 'HTTP is blocked by the mobile platform. Enable local HTTP dev settings or use HTTPS.';
    }
    if (text.contains('401')) {
      return 'Backend rejected the request. Check AGENT_PERCEPTION_TOKEN.';
    }
    return text.replaceFirst('Exception: ', '');
  }

  void _applyEvent(AgentStreamEvent event) {
    if (!mounted) return;
    ChatMessage? completedAssistant;
    setState(() {
      switch (event.type) {
        case 'TEXT_MESSAGE_START':
          _currentAssistant ??= _startAssistantMessage();
          _currentAssistant!
            ..content = ''
            ..isStreaming = true;
          break;
        case 'TEXT_MESSAGE_CONTENT':
          _currentAssistant ??= _startAssistantMessage();
          final streamingAssistant = _currentAssistant!;
          streamingAssistant.content += event.data['delta']?.toString() ?? '';
          if (!streamingAssistant.leakCheckResolved) {
            if (_looksLikeAgentActionLeak(streamingAssistant.content)) {
              streamingAssistant.content = '';
            } else if (streamingAssistant.content.trim().length >
                _leakCheckWindowChars) {
              // Past this point the message is clearly real prose, not a
              // leaked raw payload. Stop scanning it so later content can
              // never trigger a wipe (this is what caused the streaming
              // glitch where text would flash and disappear mid-reply).
              streamingAssistant.leakCheckResolved = true;
            }
          }
          break;
        case 'TEXT_MESSAGE_END':
          _currentAssistant?.isStreaming = false;
          if (_currentAssistant?.content.trim().isNotEmpty ?? false) {
            completedAssistant = _currentAssistant;
          }
          break;
        case 'TOOL_CALL_START':
          final assistant = _currentAssistant ??= _startAssistantMessage();
          final toolId =
              event.data['toolCallId']?.toString() ??
              event.data['tool_call_id']?.toString();
          assistant.tools.add(
            ToolDecoration(
              id: toolId,
              name:
                  event.data['toolCallName']?.toString() ??
                  event.data['tool_call_name']?.toString() ??
                  'tool',
              status: ToolStatus.running,
            ),
          );
          break;
        case 'TOOL_CALL_ARGS':
          final assistant = _currentAssistant ??= _startAssistantMessage();
          final toolId =
              event.data['toolCallId']?.toString() ??
              event.data['tool_call_id']?.toString();
          final delta = event.data['delta']?.toString() ?? '';
          final tool =
              _findTool(assistant, toolId) ?? _lastRunningTool(assistant);
          if (tool != null) tool.args += delta;
          break;
        case 'TOOL_CALL_END':
          break;
        case 'TOOL_CALL_RESULT':
          final assistant = _currentAssistant ??= _startAssistantMessage();
          final content = event.data['content']?.toString() ?? '';
          final toolId =
              event.data['toolCallId']?.toString() ??
              event.data['tool_call_id']?.toString();
          final runningTool =
              _findTool(assistant, toolId) ?? _lastRunningTool(assistant);
          if (runningTool == null) {
            assistant.tools.add(
              ToolDecoration(
                name: 'tool',
                status: ToolStatus.done,
                content: content,
              ),
            );
          } else {
            runningTool
              ..status = ToolStatus.done
              ..content = content;
          }
          break;
        case 'STATE_SNAPSHOT':
          final assistant = _currentAssistant ??= _startAssistantMessage();
          final card = cardFromSnapshot(event.data['snapshot']);
          assistant.hitlCard = card.isEmpty ? null : card;
          break;
        case 'RUN_ERROR':
          _messages.add(
            ChatMessage(
              id: _newId(),
              role: ChatRole.system,
              content: event.data['message']?.toString() ?? 'Agent run failed.',
              isError: true,
            ),
          );
          break;
        default:
          break;
      }
    });
    if (completedAssistant != null) {
      unawaited(_autoReadAssistant(completedAssistant!));
    }
    _scrollToBottom();
  }

  ToolDecoration? _findTool(ChatMessage assistant, String? toolId) {
    if (toolId == null) return null;
    for (final tool in assistant.tools.reversed) {
      if (tool.id == toolId) return tool;
    }
    return null;
  }

  ToolDecoration? _lastRunningTool(ChatMessage assistant) {
    for (final tool in assistant.tools.reversed) {
      if (tool.status == ToolStatus.running) return tool;
    }
    return null;
  }

  /// Max chars of accumulated content over which we still consider it
  /// plausible that the whole message is a leaked raw tool/command payload.
  /// Once a message exceeds this, treat it as genuine prose and never wipe.
  static const int _leakCheckWindowChars = 80;

  bool _looksLikeAgentActionLeak(String content) {
    final normalized = content.trimLeft().toLowerCase();
    return normalized.startsWith('command(') ||
        normalized.startsWith('tool(') ||
        normalized.contains('command(update=') ||
        normalized.contains('"todos"') && normalized.contains('"status"') ||
        normalized.contains("'todos'") && normalized.contains("'status'");
  }

  ChatMessage _startAssistantMessage() {
    final message = ChatMessage(
      id: _newId(),
      role: ChatRole.assistant,
      isStreaming: true,
    );
    _messages.add(message);
    return message;
  }

  void _sendApproval(String decision) {
    _sendChat('[System: User $decision Action]');
  }

  void _stopCurrentRun() {
    _activeRunToken++;
    setState(() {
      _currentAssistant?.isStreaming = false;
      _currentAssistant = null;
      _isSending = false;
    });
  }

  Future<void> _shareCurrentLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final location = await widget.locationService.requestCurrentLocation();
      if (!mounted) return;
      setState(() {
        _sharedLocation = location;
        _sendLocationWithNextReply = true;
        _isLocating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location saved for your next reply.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _isLocating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  HitlCardData? _latestHitlCard() {
    for (final message in _messages.reversed) {
      final card = message.hitlCard;
      if (card != null && !card.isEmpty) return card;
    }
    return null;
  }

  void _showChecklistSheet() {
    final card = _latestHitlCard();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PetTheme.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: card == null ? 0.34 : 0.62,
        minChildSize: 0.28,
        maxChildSize: 0.9,
        builder: (context, scrollController) => SafeArea(
          top: false,
          child: ListView(
            key: const ValueKey('agent-checklist-scroll'),
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              if (card == null)
                const _EmptyChecklistSheet()
              else
                HitlCard(
                  data: card,
                  onApprove: () {
                    Navigator.of(sheetContext).pop();
                    _sendApproval('Approved');
                  },
                  onModify: () {
                    Navigator.of(sheetContext).pop();
                    _showModifySheet();
                  },
                  onCancel: () {
                    Navigator.of(sheetContext).pop();
                    _sendApproval('Cancelled');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  String? _locationContextMessage(PetAgentLocation? location) {
    if (location == null) return null;
    return '[location-context] User allowed current device location. '
        'Use latitude ${location.latitude.toStringAsFixed(6)}, '
        'longitude ${location.longitude.toStringAsFixed(6)} '
        'with accuracy ${location.accuracyMeters.toStringAsFixed(0)} meters '
        'for nearby recommendations.';
  }

  bool _shouldAskForLocation(ChatMessage message) {
    if (_sharedLocation != null || message.role != ChatRole.assistant) {
      return false;
    }
    final content = message.content.toLowerCase();
    final asksInText =
        content.contains('location') ||
        content.contains('where are you') ||
        content.contains('nearby') ||
        content.contains('near you');
    final asksInTools = message.tools.any((tool) {
      final name = tool.name.toLowerCase();
      final args = tool.args.toLowerCase();
      return name.contains('clinic') ||
          name.contains('nearby') ||
          args.contains('location') ||
          args.contains('nearby');
    });
    return asksInText || asksInTools;
  }

  void _showModifySheet() {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PetTheme.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Modify action',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Tell the agent what to change',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  final text = controller.text.trim();
                  Navigator.of(context).pop();
                  if (text.isNotEmpty) {
                    _sendChat('[System: Modify Action] $text');
                  }
                },
                child: const Text('Send update'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _beginPushToTalk() {
    if (_isSending || _isDictationHeld) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _isDictationHeld = true;
    unawaited(_startDictation());
  }

  Future<void> _startDictation() async {
    await _stopSpeechPlayback();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!_isDictationHeld || _isSending || !mounted) return;
    _dictationBaseText = _inputController.text.trimRight();
    setState(() {
      _isListening = true;
      _soundLevel = 0;
    });

    try {
      await _speechToTextService.listen(
        onResult: (transcript, isFinal) {
          if (!mounted || _isDisposed) return;
          setState(() {
            _setInputText(_mergeDictation(_dictationBaseText, transcript));
          });
        },
        onListeningChanged: _setListening,
        onSoundLevelChanged: (level) {
          if (!mounted || _isDisposed) return;
          setState(() => _soundLevel = level);
        },
        onError: (error) {
          if (!mounted || _isDisposed) return;
          _isDictationHeld = false;
          _setListening(false);
          _showSpeechError(error);
        },
      );
    } on Object catch (error) {
      if (!mounted || _isDisposed) return;
      _isDictationHeld = false;
      _setListening(false);
      _showSpeechError(error);
    }
  }

  /// Ends dictation and sends whatever transcript was captured. Used both
  /// by releasing the hold-to-talk button and by tapping "confirm" in
  /// tap-to-confirm mode.
  void _endPushToTalk() {
    if (!_isDictationHeld && !_isListening) return;
    _isDictationHeld = false;
    unawaited(_stopDictation());
  }

  /// Ends dictation and discards the transcript instead of sending it.
  /// Used by the "cancel" button in tap-to-confirm mode.
  void _cancelDictation() {
    if (!_isDictationHeld && !_isListening) return;
    _isDictationHeld = false;
    unawaited(_discardDictation());
  }

  Future<void> _stopDictation() async {
    var stoppedCleanly = false;
    try {
      await _speechToTextService.stop();
      stoppedCleanly = true;
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlySpeechError(error))));
      }
    } finally {
      _setListening(false);
    }
  }

  Future<void> _discardDictation() async {
    try {
      await _speechToTextService.cancel();
    } on Object catch (_) {
      // Best-effort discard — nothing actionable to show the user here.
    } finally {
      if (mounted && !_isDisposed) {
        _setInputText(_dictationBaseText);
      }
      _setListening(false);
    }
  }

  void _setListening(bool isListening) {
    if (!mounted || _isDisposed) return;
    setState(() {
      _isListening = isListening;
      if (!isListening) _soundLevel = 0;
    });
  }

  void _showSpeechError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_friendlySpeechError(error))));
  }

  void _setInputText(String text) {
    _inputController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  String _mergeDictation(String baseText, String transcript) {
    final trimmedTranscript = transcript.trim();
    if (trimmedTranscript.isEmpty) return baseText;
    if (baseText.isEmpty) return trimmedTranscript;
    return '$baseText $trimmedTranscript';
  }

  String _friendlySpeechError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    if (text.contains('permission') || text.contains('Permission')) {
      return 'Microphone or speech permission was not granted.';
    }
    return text;
  }

  Future<void> _autoReadAssistant(ChatMessage message) async {
    await _autoReadReady;
    if (!mounted ||
        !_autoReadEnabled ||
        message.content.trim().isEmpty ||
        !_autoReadMessageIds.add(message.id)) {
      return;
    }
    await _playAssistantMessage(message);
  }

  Future<void> _toggleAutoRead(ChatMessage message) async {
    if (_autoReadEnabled) {
      setState(() => _autoReadEnabled = false);
      await _stopSpeechPlayback();
      await _writeAutoReadPreference(false);
      return;
    }

    setState(() => _autoReadEnabled = true);
    await _writeAutoReadPreference(true);
    await _playAssistantMessage(message);
  }

  Future<void> _writeAutoReadPreference(bool enabled) async {
    try {
      await _autoReadPreferenceStore.writeEnabled(enabled);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save audio preference: $error')),
      );
    }
  }

  Future<void> _playAssistantMessage(ChatMessage message) async {
    await _stopSpeechPlayback();
    if (!mounted || _isDisposed) return;
    final token = ++_speechPlaybackToken;
    setState(() => _speakingMessageId = message.id);
    try {
      await _textToSpeechService.speak(message.content);
    } on Object catch (error) {
      if (!mounted || token != _speechPlaybackToken) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyTextToSpeechError(error))),
      );
    } finally {
      if (mounted && token == _speechPlaybackToken) {
        setState(() => _speakingMessageId = null);
      }
    }
  }

  Future<void> _stopSpeechPlayback() async {
    _speechPlaybackToken += 1;
    try {
      await _textToSpeechService.stop();
    } on Object catch (error) {
      debugPrint('Could not stop voice playback: $error');
    }
    if (mounted && _speakingMessageId != null) {
      setState(() => _speakingMessageId = null);
    }
  }

  String _friendlyTextToSpeechError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    if (text.contains('Connection refused') ||
        text.contains('Failed host lookup') ||
        text.contains('SocketException')) {
      return 'Voice playback is unavailable. Check TTS_BASE_URL and that Kokoro is running.';
    }
    return 'Voice playback is unavailable. $text';
  }

  void _openGalleryFlow() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CaptureScreen(
          client: widget.client,
          streakClient: widget.streakClient,
          visualLlmClient: widget.visualLlmClient,
          textToSpeechService: _textToSpeechService,
          autoReadPreferenceStore: _autoReadPreferenceStore,
          openGalleryOnStart: true,
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  String _newId() => newAgentId();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pet Agent'),
        actions: [
          _ChecklistActionButton(
            card: _latestHitlCard(),
            onPressed: _showChecklistSheet,
          ),
          Builder(
            builder: (context) {
              return IconButton(
                tooltip: 'Chat menu',
                onPressed: () => Scaffold.of(context).openEndDrawer(),
                icon: const Icon(Icons.menu),
              );
            },
          ),
        ],
      ),
      endDrawer: _ChatMenuDrawer(threadId: _threadId),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth > 700
                        ? 680
                        : double.infinity,
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: _messages.isEmpty
                            ? const _EmptyChatState()
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  12,
                                ),
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  return ChatMessageView(
                                    message: _messages[index],
                                    showLocationPrompt: _shouldAskForLocation(
                                      _messages[index],
                                    ),
                                    isLocating: _isLocating,
                                    autoReadEnabled: _autoReadEnabled,
                                    isSpeaking:
                                        _speakingMessageId ==
                                        _messages[index].id,
                                    onShareLocation: _shareCurrentLocation,
                                    onBookRecommendation: _sendChat,
                                    onToggleAutoRead: _toggleAutoRead,
                                  );
                                },
                              ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: ChatComposer(
                            controller: _inputController,
                            isSending: _isSending,
                            isListening: _isListening,
                            soundLevel: _soundLevel,
                            onGallery: _openGalleryFlow,
                            onHoldStart: _beginPushToTalk,
                            onHoldEnd: _endPushToTalk,
                            onTapStart: _beginPushToTalk,
                            onConfirmListening: _endPushToTalk,
                            onCancelListening: _cancelDictation,
                            onSend: () =>
                                unawaited(_sendChat(_inputController.text)),
                            onStop: _stopCurrentRun,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Rendered centered on screen — away from the push-to-talk
              // button entirely — and non-interactive, so it can never
              // intercept the pointer release that ends the long press.
              if (_isListening)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: VoiceListeningPanel(
                          transcript: _inputController.text,
                          soundLevel: _soundLevel,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pets, color: PetTheme.aqua, size: 42),
            SizedBox(height: 14),
            Text(
              'Ask about your pet or send a captured moment.',
              textAlign: TextAlign.center,
              style: TextStyle(color: PetTheme.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistActionButton extends StatelessWidget {
  const _ChecklistActionButton({required this.card, required this.onPressed});

  final HitlCardData? card;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final count = card?.todos.length ?? 0;
    return IconButton(
      tooltip: 'Agent checklist',
      onPressed: onPressed,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(count == 0 ? Icons.checklist_rtl : Icons.fact_check_outlined),
          if (count > 0)
            Positioned(
              right: -7,
              top: -7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: PetTheme.warning,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  child: Text(
                    count > 9 ? '9+' : count.toString(),
                    style: const TextStyle(
                      color: Color(0xFF10141A),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyChecklistSheet extends StatelessWidget {
  const _EmptyChecklistSheet();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.checklist_rtl, color: PetTheme.muted, size: 34),
        SizedBox(height: 12),
        Text('No active checklist'),
        SizedBox(height: 6),
        Text(
          'Agent steps will appear here when approval or follow-up tasks are needed.',
          textAlign: TextAlign.center,
          style: TextStyle(color: PetTheme.muted, height: 1.35),
        ),
      ],
    );
  }
}

class ChatMessageView extends StatelessWidget {
  const ChatMessageView({
    required this.message,
    required this.showLocationPrompt,
    required this.isLocating,
    required this.autoReadEnabled,
    required this.isSpeaking,
    required this.onShareLocation,
    required this.onBookRecommendation,
    required this.onToggleAutoRead,
    super.key,
  });

  final ChatMessage message;
  final bool showLocationPrompt;
  final bool isLocating;
  final bool autoReadEnabled;
  final bool isSpeaking;
  final Future<void> Function() onShareLocation;
  final ValueChanged<String> onBookRecommendation;
  final ValueChanged<ChatMessage> onToggleAutoRead;

  @override
  Widget build(BuildContext context) {
    return switch (message.role) {
      ChatRole.user => UserMessageBubble(message: message),
      ChatRole.system => SystemMessageCard(message: message),
      ChatRole.assistant => AssistantResponseBlock(
        message: message,
        showLocationPrompt: showLocationPrompt,
        isLocating: isLocating,
        autoReadEnabled: autoReadEnabled,
        isSpeaking: isSpeaking,
        onShareLocation: onShareLocation,
        onBookRecommendation: onBookRecommendation,
        onToggleAutoRead: onToggleAutoRead,
      ),
    };
  }
}

class UserMessageBubble extends StatelessWidget {
  const UserMessageBubble({required this.message, super.key});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF20313A),
            border: Border.all(color: const Color(0xFF2B3440)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.attachmentLabel != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: PetMomentCard(
                    label: message.attachmentLabel!,
                    capture: message.capture,
                  ),
                ),
              if (message.content.isNotEmpty && message.capture == null)
                MarkdownBody(
                  data: message.content,
                  selectable: true,
                  styleSheet: _chatMarkdownStyle(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SystemMessageCard extends StatelessWidget {
  const SystemMessageCard({required this.message, super.key});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: message.isError ? const Color(0xFF381C1C) : PetTheme.panel,
            border: Border.all(
              color: message.isError ? PetTheme.coral : const Color(0xFF2B3440),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: MarkdownBody(
            data: message.content,
            selectable: true,
            styleSheet: _chatMarkdownStyle(context),
          ),
        ),
      ),
    );
  }
}

class AssistantResponseBlock extends StatelessWidget {
  const AssistantResponseBlock({
    required this.message,
    required this.showLocationPrompt,
    required this.isLocating,
    required this.autoReadEnabled,
    required this.isSpeaking,
    required this.onShareLocation,
    required this.onBookRecommendation,
    required this.onToggleAutoRead,
    super.key,
  });

  final ChatMessage message;
  final bool showLocationPrompt;
  final bool isLocating;
  final bool autoReadEnabled;
  final bool isSpeaking;
  final Future<void> Function() onShareLocation;
  final ValueChanged<String> onBookRecommendation;
  final ValueChanged<ChatMessage> onToggleAutoRead;

  @override
  Widget build(BuildContext context) {
    final recommendations = recommendationsFromTools(message.tools);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.isStreaming && message.content.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Analyzing...',
                        style: TextStyle(color: PetTheme.muted),
                      ),
                    ],
                  ),
                ),
              if (message.tools.isNotEmpty) ...[
                AgentActivityPanel(tools: message.tools),
                const SizedBox(height: 8),
              ],
              if (message.content.isNotEmpty && message.capture == null)
                AnimatedOpacity(
                  opacity: message.isStreaming ? 0 : 1,
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  child: AnimatedSlide(
                    offset: message.isStreaming
                        ? const Offset(0, 0.01)
                        : Offset.zero,
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    child: MarkdownBody(
                      data: message.content,
                      selectable: true,
                      styleSheet: _chatMarkdownStyle(context),
                    ),
                  ),
                ),
              if (_showCopyAction)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _AssistantResponseActions(
                    content: message.content,
                    autoReadEnabled: autoReadEnabled,
                    isSpeaking: isSpeaking,
                    onToggleAutoRead: () => onToggleAutoRead(message),
                  ),
                ),
              if (recommendations.isNotEmpty) ...[
                const SizedBox(height: 10),
                RecommendationSection(
                  recommendations: recommendations,
                  onBook: onBookRecommendation,
                ),
              ],
              if (showLocationPrompt && !message.isStreaming) ...[
                const SizedBox(height: 10),
                LocationPermissionCard(
                  isLocating: isLocating,
                  onAllow: onShareLocation,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool get _showCopyAction =>
      !message.isStreaming && message.content.trim().isNotEmpty;
}

MarkdownStyleSheet _chatMarkdownStyle(BuildContext context) {
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: const TextStyle(color: PetTheme.ivory, height: 1.35),
    code: const TextStyle(
      color: PetTheme.aqua,
      backgroundColor: Color(0xFF10141A),
    ),
  );
}

class _AssistantResponseActions extends StatelessWidget {
  const _AssistantResponseActions({
    required this.content,
    required this.autoReadEnabled,
    required this.isSpeaking,
    required this.onToggleAutoRead,
  });

  final String content;
  final bool autoReadEnabled;
  final bool isSpeaking;
  final VoidCallback onToggleAutoRead;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Copy response',
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: content));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Response copied.')));
          },
          icon: const Icon(Icons.copy_all_outlined, color: PetTheme.muted),
        ),
        IconButton(
          tooltip: autoReadEnabled ? 'Mute auto-read' : 'Read response aloud',
          iconSize: 19,
          visualDensity: VisualDensity.compact,
          onPressed: onToggleAutoRead,
          icon: Icon(
            autoReadEnabled
                ? Icons.volume_off_outlined
                : Icons.volume_up_outlined,
            color: isSpeaking ? PetTheme.aqua : PetTheme.muted,
          ),
        ),
      ],
    );
  }
}

class PetMomentCard extends StatelessWidget {
  const PetMomentCard({required this.label, required this.capture, super.key});

  final String label;
  final PetCaptureResult? capture;

  @override
  Widget build(BuildContext context) {
    final result = capture;
    final kindLabel = switch (result?.kind) {
      CaptureMediaKind.video => 'Video moment',
      CaptureMediaKind.image => 'Photo moment',
      CaptureMediaKind.demo => 'Demo moment',
      null => 'Pet moment',
    };

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF10141A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2B3440)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(8),
            ),
            child: SizedBox(
              width: 88,
              height: 88,
              child: _PetMomentThumbnail(capture: result),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kindLabel,
                    style: const TextStyle(
                      color: PetTheme.aqua,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result?.userDescription ?? label,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PetTheme.ivory, height: 1.25),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PetMomentThumbnail extends StatelessWidget {
  const _PetMomentThumbnail({required this.capture});

  final PetCaptureResult? capture;

  @override
  Widget build(BuildContext context) {
    final result = capture;
    if (result?.kind == CaptureMediaKind.image && result?.path != null) {
      return Image.file(File(result!.path!), fit: BoxFit.cover);
    }
    final isVideo = result?.kind == CaptureMediaKind.video;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF17333A), Color(0xFF6E3328)],
        ),
      ),
      child: Center(
        child: Icon(
          isVideo ? Icons.play_circle_outline : Icons.pets,
          color: PetTheme.ivory,
          size: 30,
        ),
      ),
    );
  }
}

class AgentActivityPanel extends StatefulWidget {
  const AgentActivityPanel({required this.tools, super.key});

  final List<ToolDecoration> tools;

  @override
  State<AgentActivityPanel> createState() => _AgentActivityPanelState();
}

class _AgentActivityPanelState extends State<AgentActivityPanel> {
  bool? _expandedOverride;

  bool get _hasRunning =>
      widget.tools.any((tool) => tool.status == ToolStatus.running);

  @override
  Widget build(BuildContext context) {
    final completeCount = widget.tools
        .where((tool) => tool.status == ToolStatus.done)
        .length;
    final expanded = _expandedOverride ?? true;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF10141A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2B3440)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expandedOverride = !expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    _hasRunning ? Icons.sync : Icons.check_circle,
                    color: _hasRunning ? PetTheme.warning : PetTheme.sage,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _hasRunning ? 'Agent is working' : 'Agent steps complete',
                      style: const TextStyle(
                        color: PetTheme.ivory,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '$completeCount/${widget.tools.length}',
                    style: const TextStyle(color: PetTheme.muted),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: PetTheme.muted,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: [
                  for (var index = 0; index < widget.tools.length; index++)
                    ToolTimelineStep(
                      tool: widget.tools[index],
                      isLast: index == widget.tools.length - 1,
                    ),
                ],
              ),
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 160),
          ),
        ],
      ),
    );
  }
}

class ToolTimelineStep extends StatelessWidget {
  const ToolTimelineStep({required this.tool, required this.isLast, super.key});

  final ToolDecoration tool;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final done = tool.status == ToolStatus.done;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.radio_button_checked,
                color: done ? PetTheme.sage : PetTheme.warning,
                size: 18,
              ),
              if (!isLast)
                const Expanded(
                  child: VerticalDivider(
                    width: 18,
                    thickness: 1,
                    color: Color(0xFF2B3440),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _toolTitle(tool.name),
                    style: const TextStyle(
                      color: PetTheme.ivory,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    done ? _toolSummary(tool.content) : _argsSummary(tool.args),
                    maxLines: done ? 4 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PetTheme.muted, height: 1.3),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _toolTitle(String name) {
    return name
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _argsSummary(String args) {
    if (args.trim().isEmpty) return 'Preparing request...';
    final todoSummary = _todoSummary(args);
    if (todoSummary != null) return todoSummary;
    final decoded = _tryJson(args);
    if (decoded is Map<String, dynamic> && decoded.isNotEmpty) {
      return decoded.entries
          .take(3)
          .map((entry) => '${entry.key}: ${_compact(entry.value)}')
          .join(' • ');
    }
    return args;
  }

  String? _todoSummary(String text) {
    if (!text.toLowerCase().contains('todo')) return null;
    final matches = RegExp(
      r"""content['"]?\s*:\s*['"]([^'"]+)['"]""",
      caseSensitive: false,
    ).allMatches(text);
    final items = matches.map((match) => match.group(1)).nonNulls.toList();
    if (items.isEmpty) return 'Updating checklist.';
    return items.take(3).join(' • ');
  }

  String _toolSummary(String content) {
    if (content.trim().isEmpty) return 'Completed.';
    final todoSummary = _todoSummary(content);
    if (todoSummary != null) return todoSummary;
    final decoded = _tryJson(content);
    if (decoded == null) return content;
    if (decoded is Map<String, dynamic>) {
      final status = decoded['status'];
      final message =
          decoded['message'] ??
          decoded['summary'] ??
          decoded['name'] ??
          decoded['result'];
      if (message != null) {
        return status == null
            ? _compact(message)
            : '$status: ${_compact(message)}';
      }
      return decoded.entries
          .take(3)
          .map((entry) => '${entry.key}: ${_compact(entry.value)}')
          .join(' • ');
    }
    if (decoded is List) return 'Found ${decoded.length} result(s).';
    return _compact(decoded);
  }

  Object? _tryJson(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  String _compact(Object? value) {
    final text = value is String ? value : jsonEncode(value);
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class Recommendation {
  const Recommendation({
    required this.name,
    this.subtitle,
    this.address,
    this.phone,
    this.url,
  });

  factory Recommendation.fromJson(Map<String, dynamic> json) {
    final name =
        json['name'] ??
        json['title'] ??
        json['clinic_name'] ??
        json['shop_name'] ??
        json['provider'] ??
        'Recommended place';
    return Recommendation(
      name: name.toString(),
      subtitle:
          (json['summary'] ??
                  json['rating'] ??
                  json['type'] ??
                  json['category'])
              ?.toString(),
      address:
          (json['address'] ?? json['formatted_address'] ?? json['vicinity'])
              ?.toString(),
      phone: (json['phone'] ?? json['phone_number'] ?? json['contact'])
          ?.toString(),
      url: (json['url'] ?? json['website'] ?? json['google_url'])?.toString(),
    );
  }

  final String name;
  final String? subtitle;
  final String? address;
  final String? phone;
  final String? url;

  String get detailsUrl =>
      url ?? 'https://www.google.com/search?q=${Uri.encodeComponent(name)}';
}

List<Recommendation> recommendationsFromTools(List<ToolDecoration> tools) {
  final recommendations = <Recommendation>[];

  void collect(Object? value, {required bool allowPlaceCards}) {
    if (value is Map<String, dynamic>) {
      final nestedAllowsPlaceCards =
          allowPlaceCards || _hasRecommendationContainerKey(value);
      final label =
          value['name'] ??
          value['title'] ??
          value['clinic_name'] ??
          value['shop_name'] ??
          value['provider'];
      if (label != null &&
          nestedAllowsPlaceCards &&
          _looksLikeStoreOption(value)) {
        recommendations.add(Recommendation.fromJson(value));
      }
      for (final nested in value.values) {
        if (nested is List || nested is Map<String, dynamic>) {
          collect(nested, allowPlaceCards: nestedAllowsPlaceCards);
        }
      }
    } else if (value is List) {
      for (final item in value) {
        collect(item, allowPlaceCards: allowPlaceCards);
      }
    }
  }

  for (final tool in tools) {
    if (tool.status != ToolStatus.done || tool.content.trim().isEmpty) continue;
    collect(
      _decodeRecommendationJson(tool.content),
      allowPlaceCards: _toolCanReturnStoreOptions(tool.name),
    );
  }

  final seen = <String>{};
  return recommendations.where((item) => seen.add(item.name)).take(3).toList();
}

bool _toolCanReturnStoreOptions(String name) {
  final normalized = name.toLowerCase();
  const words = [
    'clinic',
    'shop',
    'store',
    'place',
    'maps',
    'nearby',
    'supply',
    'booking',
    'emergency',
    'vet',
  ];
  return words.any(normalized.contains);
}

bool _hasRecommendationContainerKey(Map<String, dynamic> value) {
  const keys = {
    'clinics',
    'shops',
    'stores',
    'places',
    'providers',
    'recommendations',
    'results',
  };
  return value.keys.any(keys.contains);
}

bool _looksLikeStoreOption(Map<String, dynamic> value) {
  final label =
      value['name'] ??
      value['title'] ??
      value['clinic_name'] ??
      value['shop_name'] ??
      value['provider'];
  final labelText = label?.toString().toLowerCase() ?? '';
  final placeWords = ['clinic', 'shop', 'hospital', 'vet', 'pet'];
  if (placeWords.any(labelText.contains)) return true;

  const placeKeys = {
    'address',
    'formatted_address',
    'vicinity',
    'phone',
    'phone_number',
    'contact',
    'website',
    'url',
    'google_url',
    'rating',
    'distance',
    'opening_hours',
    'clinic_name',
    'shop_name',
    'provider',
  };
  return value.keys.any(placeKeys.contains);
}

Object? _decodeRecommendationJson(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

class RecommendationSection extends StatelessWidget {
  const RecommendationSection({
    required this.recommendations,
    required this.onBook,
    super.key,
  });

  final List<Recommendation> recommendations;
  final ValueChanged<String> onBook;

  @override
  Widget build(BuildContext context) {
    if (recommendations.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recommendations', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final recommendation in recommendations)
          RecommendationCard(recommendation: recommendation, onBook: onBook),
      ],
    );
  }
}

class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    required this.recommendation,
    required this.onBook,
    super.key,
  });

  final Recommendation recommendation;
  final ValueChanged<String> onBook;

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PetTheme.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              recommendation.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (recommendation.address != null)
              Text(
                recommendation.address!,
                style: const TextStyle(color: PetTheme.muted),
              ),
            if (recommendation.phone != null) ...[
              const SizedBox(height: 6),
              Text(
                recommendation.phone!,
                style: const TextStyle(color: PetTheme.muted),
              ),
            ],
            const SizedBox(height: 12),
            SelectableText(
              recommendation.detailsUrl,
              style: const TextStyle(color: PetTheme.aqua),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121B24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2B3440)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront, color: PetTheme.aqua, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    recommendation.name,
                    style: const TextStyle(
                      color: PetTheme.ivory,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (recommendation.subtitle != null ||
                recommendation.address != null) ...[
              const SizedBox(height: 5),
              Text(
                recommendation.subtitle ?? recommendation.address!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PetTheme.muted, height: 1.25),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _showDetails(context),
                  child: const Text('Shop details'),
                ),
                FilledButton(
                  onPressed: () =>
                      onBook('Help me book ${recommendation.name}.'),
                  child: const Text('Book now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LocationPermissionCard extends StatelessWidget {
  const LocationPermissionCard({
    required this.isLocating,
    required this.onAllow,
    super.key,
  });

  final bool isLocating;
  final Future<void> Function() onAllow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF111722),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PetTheme.aqua),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, color: PetTheme.aqua),
              const SizedBox(width: 8),
              Text(
                'Share current location?',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'The agent can use your exact device location to find nearby clinics and pet shops.',
            style: TextStyle(color: PetTheme.muted, height: 1.35),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: isLocating ? null : onAllow,
              child: isLocating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Allow once'),
            ),
          ),
        ],
      ),
    );
  }
}

class HitlCard extends StatefulWidget {
  const HitlCard({
    required this.data,
    required this.onApprove,
    required this.onModify,
    required this.onCancel,
    super.key,
  });

  final HitlCardData data;
  final VoidCallback onApprove;
  final VoidCallback onModify;
  final VoidCallback onCancel;

  @override
  State<HitlCard> createState() => _HitlCardState();
}

class _HitlCardState extends State<HitlCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final todos = widget.data.todos;
    final visibleTodos = _expanded ? todos : todos.take(3).toList();
    final hiddenCount = todos.length - visibleTodos.length;

    return Material(
      elevation: 1,
      color: const Color(0xFF111722),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: PetTheme.warning),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.data.title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              widget.data.body,
              style: const TextStyle(color: PetTheme.muted, height: 1.35),
            ),
            if (visibleTodos.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final todo in visibleTodos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        todo.completed
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: todo.completed ? PetTheme.sage : PetTheme.muted,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(todo.content)),
                    ],
                  ),
                ),
              if (todos.length > 3)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    label: Text(
                      _expanded ? 'Show less' : 'Show $hiddenCount more',
                    ),
                  ),
                ),
            ],
            if (widget.data.payloadPreview != null) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('View payload'),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.data.payloadPreview!,
                      style: const TextStyle(
                        color: PetTheme.muted,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
                OutlinedButton(
                  onPressed: widget.onModify,
                  child: const Text('Modify'),
                ),
                FilledButton(
                  onPressed: widget.onApprove,
                  child: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMenuDrawer extends StatelessWidget {
  const _ChatMenuDrawer({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: PetTheme.panel,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Chats',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Current chat'),
              subtitle: Text(
                threadId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Previous chats will appear here after the backend exposes thread history APIs.',
                style: TextStyle(color: PetTheme.muted, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}