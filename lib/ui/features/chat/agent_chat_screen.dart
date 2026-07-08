import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../data/services/agent_stream_client.dart';
import '../../../domain/models/pet_capture_result.dart';
import '../../core/pet_theme.dart';
import '../capture/capture_screen.dart';

class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({required this.client, this.initialCapture, super.key});

  final AgentStreamClient client;
  final PetCaptureResult? initialCapture;

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

  @override
  void initState() {
    super.initState();
    final capture = widget.initialCapture;
    if (capture != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendPerception(capture);
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendPerception(PetCaptureResult capture) async {
    if (_isSending) return;
    final payload = capture.toPerceptionPayload(_threadId);
    final userMessage = ChatMessage(
      id: _newId(),
      role: ChatRole.user,
      content:
          '[perception-event]\n${const JsonEncoder.withIndent('  ').convert(payload)}',
      attachmentLabel: capture.attachmentLabel,
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

    _inputController.clear();
    setState(() {
      _messages.add(
        ChatMessage(id: _newId(), role: ChatRole.user, content: trimmed),
      );
      _isSending = true;
    });
    _scrollToBottom();

    final payload = buildRunAgentInput(
      threadId: _threadId,
      runId: _newId(),
      messages: _messages,
    );
    await _consume(path: '/agent', payload: payload);
  }

  Future<void> _consume({
    required String path,
    required Map<String, dynamic> payload,
  }) async {
    var endedCleanly = false;
    try {
      await widget.client.streamAgent(
        path: path,
        payload: payload,
        onEvent: (event) {
          if (event.type == 'TEXT_MESSAGE_END' ||
              event.type == 'RUN_FINISHED') {
            endedCleanly = true;
          }
          _applyEvent(event);
        },
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        if (_currentAssistant != null) _messages.remove(_currentAssistant);
        _currentAssistant = null;
        _isSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network unstable. Please try again.')),
      );
      return;
    }

    if (!mounted) return;
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
  }

  void _applyEvent(AgentStreamEvent event) {
    if (!mounted) return;
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
          _currentAssistant!.content += event.data['delta']?.toString() ?? '';
          break;
        case 'TEXT_MESSAGE_END':
          _currentAssistant?.isStreaming = false;
          break;
        case 'TOOL_CALL_START':
          final assistant = _currentAssistant ??= _startAssistantMessage();
          assistant.tools.add(
            ToolDecoration(
              name: event.data['toolCallName']?.toString() ?? 'tool',
              status: ToolStatus.running,
            ),
          );
          break;
        case 'TOOL_CALL_RESULT':
          final assistant = _currentAssistant ??= _startAssistantMessage();
          final content = event.data['content']?.toString() ?? '';
          ToolDecoration? runningTool;
          for (final tool in assistant.tools.reversed) {
            if (tool.status == ToolStatus.running) {
              runningTool = tool;
              break;
            }
          }
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
          assistant.hitlCard = cardFromSnapshot(event.data['snapshot']);
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
    _scrollToBottom();
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

  void _openVoiceOverlay() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PetTheme.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (context) => const _VoicePendingSheet(),
    );
  }

  void _openCaptureFlow() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CaptureScreen(client: widget.client),
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
          IconButton(
            tooltip: 'Capture pet moment',
            onPressed: _openCaptureFlow,
            icon: const Icon(Icons.photo_camera_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth > 700 ? 680 : double.infinity,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: _messages.isEmpty
                        ? const _EmptyChatState()
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              return ChatBubble(
                                message: _messages[index],
                                onApprove: () => _sendApproval('Approved'),
                                onModify: _showModifySheet,
                                onCancel: () => _sendApproval('Cancelled'),
                              );
                            },
                          ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: _InputBar(
                        controller: _inputController,
                        isSending: _isSending,
                        onCamera: _openCaptureFlow,
                        onVoice: _openVoiceOverlay,
                        onSend: () => _sendChat(_inputController.text),
                        onSubmitted: _sendChat,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.isSending,
    required this.onCamera,
    required this.onVoice,
    required this.onSend,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onCamera;
  final VoidCallback onVoice;
  final VoidCallback onSend;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Camera or gallery',
          onPressed: isSending ? null : onCamera,
          icon: const Icon(Icons.photo_camera_outlined),
        ),
        IconButton(
          tooltip: 'Voice call',
          onPressed: isSending ? null : onVoice,
          icon: const Icon(Icons.mic_none),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: onSubmitted,
            decoration: const InputDecoration(hintText: 'Ask about your pet'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Send',
          onPressed: isSending ? null : onSend,
          icon: isSending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
        ),
      ],
    );
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    required this.message,
    required this.onApprove,
    required this.onModify,
    required this.onCancel,
    super.key,
  });

  final ChatMessage message;
  final VoidCallback onApprove;
  final VoidCallback onModify;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final background = message.isError
        ? const Color(0xFF381C1C)
        : isUser
        ? const Color(0xFF20313A)
        : PetTheme.panel;
    final borderColor = message.isError
        ? PetTheme.coral
        : const Color(0xFF2B3440);

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: background,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.attachmentLabel != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AttachmentChip(label: message.attachmentLabel!),
                ),
              if (message.tools.isNotEmpty) ...[
                for (final tool in message.tools) ToolTimelineChip(tool: tool),
                const SizedBox(height: 8),
              ],
              if (message.content.isNotEmpty)
                MarkdownBody(
                  data: message.content,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                      .copyWith(
                        p: const TextStyle(color: PetTheme.ivory, height: 1.35),
                        code: const TextStyle(
                          color: PetTheme.aqua,
                          backgroundColor: Color(0xFF10141A),
                        ),
                      ),
                ),
              if (message.isStreaming && message.content.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
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
              if (message.hitlCard != null) ...[
                const SizedBox(height: 10),
                HitlCard(
                  data: message.hitlCard!,
                  onApprove: onApprove,
                  onModify: onModify,
                  onCancel: onCancel,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF10141A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2B3440)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_outlined, size: 16, color: PetTheme.aqua),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PetTheme.ivory),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ToolTimelineChip extends StatelessWidget {
  const ToolTimelineChip({required this.tool, super.key});

  final ToolDecoration tool;

  @override
  Widget build(BuildContext context) {
    final done = tool.status == ToolStatus.done;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF10141A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: done ? const Color(0xFF284A3A) : const Color(0xFF4D3C20),
        ),
      ),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.sync,
            color: done ? PetTheme.sage : PetTheme.warning,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              done && tool.content.isNotEmpty
                  ? tool.content
                  : 'Calling ${tool.name}...',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PetTheme.ivory),
            ),
          ),
        ],
      ),
    );
  }
}

class HitlCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
            Text(data.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              data.body,
              style: const TextStyle(color: PetTheme.muted, height: 1.35),
            ),
            if (data.todos.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final todo in data.todos)
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
            ],
            if (data.payloadPreview != null) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('View payload'),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      data.payloadPreview!,
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
                TextButton(onPressed: onCancel, child: const Text('Cancel')),
                OutlinedButton(
                  onPressed: onModify,
                  child: const Text('Modify'),
                ),
                FilledButton(
                  onPressed: onApprove,
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

class _VoicePendingSheet extends StatelessWidget {
  const _VoicePendingSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Waveform(),
          const SizedBox(height: 18),
          Text(
            'Live voice is queued for STT integration',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'The microphone UI is ready, but audio streaming is disabled until the backend endpoint is finalized.',
            textAlign: TextAlign.center,
            style: TextStyle(color: PetTheme.muted, height: 1.35),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(7, (index) {
        final height = 18.0 + (index.isEven ? 18 : 30);
        return Container(
          width: 7,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: index == 3 ? PetTheme.coral : PetTheme.aqua,
            borderRadius: BorderRadius.circular(8),
          ),
        );
      }),
    );
  }
}
