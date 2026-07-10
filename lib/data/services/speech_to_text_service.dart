import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart' as speech_error;
import 'package:speech_to_text/speech_to_text.dart' as speech;

typedef SpeechTranscriptCallback =
    void Function(String transcript, bool isFinal);
typedef SpeechListeningChanged = void Function(bool isListening);
typedef SpeechSoundLevelChanged = void Function(double level);
typedef SpeechRecognitionFailed = void Function(Object error);

abstract class SpeechToTextService {
  Future<void> listen({
    required SpeechTranscriptCallback onResult,
    SpeechListeningChanged? onListeningChanged,
    SpeechSoundLevelChanged? onSoundLevelChanged,
    SpeechRecognitionFailed? onError,
  });

  Future<void> stop();

  Future<void> cancel();
}

class SpeechTranscriptAccumulator {
  final _segments = <String>[];
  String _liveText = '';

  String update(String words, {required bool isFinal}) {
    _liveText = words.trim();
    if (isFinal) completeSession();
    return text;
  }

  String completeSession() {
    final completed = _liveText.trim();
    if (completed.isNotEmpty &&
        (_segments.isEmpty || _segments.last != completed)) {
      _segments.add(completed);
    }
    _liveText = '';
    return text;
  }

  String get text =>
      [..._segments, if (_liveText.isNotEmpty) _liveText].join(' ');

  void clear() {
    _segments.clear();
    _liveText = '';
  }
}

class NativeSpeechToTextService implements SpeechToTextService {
  NativeSpeechToTextService({speech.SpeechToText? speechToText})
    : _speechToText = speechToText ?? speech.SpeechToText();

  final speech.SpeechToText _speechToText;
  final SpeechTranscriptAccumulator _transcript = SpeechTranscriptAccumulator();
  bool _initialized = false;
  bool _keepListening = false;
  bool _startingSession = false;
  bool _notifiedListening = false;
  double _minimumSoundLevel = 0;
  double _maximumSoundLevel = 0;
  Timer? _restartTimer;
  SpeechTranscriptCallback? _onResult;
  SpeechListeningChanged? _onListeningChanged;
  SpeechSoundLevelChanged? _onSoundLevelChanged;
  SpeechRecognitionFailed? _onError;

  @override
  Future<void> listen({
    required SpeechTranscriptCallback onResult,
    SpeechListeningChanged? onListeningChanged,
    SpeechSoundLevelChanged? onSoundLevelChanged,
    SpeechRecognitionFailed? onError,
  }) async {
    await cancel();
    _onResult = onResult;
    _onListeningChanged = onListeningChanged;
    _onSoundLevelChanged = onSoundLevelChanged;
    _onError = onError;
    _transcript.clear();
    _minimumSoundLevel = 0;
    _maximumSoundLevel = 0;
    _keepListening = true;

    final available = await _initialize();
    if (!available) {
      _keepListening = false;
      throw const SpeechToTextServiceException(
        'Speech recognition is not available on this device.',
      );
    }
    if (!_keepListening) return;

    _notifyListening(true);
    await _startSession();
  }

  @override
  Future<void> stop() async {
    if (!_keepListening && !_notifiedListening) return;
    _keepListening = false;
    _restartTimer?.cancel();
    await _speechToText.stop();
    final transcript = _transcript.completeSession();
    _onResult?.call(transcript, true);
    _notifyListening(false);
    _onSoundLevelChanged?.call(0);
  }

  @override
  Future<void> cancel() async {
    _keepListening = false;
    _restartTimer?.cancel();
    _startingSession = false;
    if (_initialized) await _speechToText.cancel();
    _transcript.clear();
    _notifyListening(false);
    _onSoundLevelChanged?.call(0);
  }

  Future<bool> _initialize() async {
    if (_initialized) return true;
    _initialized = await _speechToText.initialize(
      onError: _handleSpeechError,
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _handleSessionEnded();
        }
      },
    );
    return _initialized;
  }

  Future<void> _startSession() async {
    if (!_keepListening || _startingSession || _speechToText.isListening) {
      return;
    }
    _startingSession = true;
    try {
      await _speechToText.listen(
        onResult: (result) {
          final combined = _transcript.update(
            result.recognizedWords,
            isFinal: result.finalResult,
          );
          _onResult?.call(combined, false);
        },
        onSoundLevelChange: _handleSoundLevel,
        listenOptions: speech.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: speech.ListenMode.dictation,
          pauseFor: const Duration(seconds: 4),
          listenFor: const Duration(minutes: 1),
          autoPunctuation: true,
        ),
      );
    } finally {
      _startingSession = false;
    }
  }

  void _handleSessionEnded() {
    if (!_keepListening) return;
    final combined = _transcript.completeSession();
    _onResult?.call(combined, false);
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 180), () {
      unawaited(_startSession());
    });
  }

  void _handleSpeechError(speech_error.SpeechRecognitionError error) {
    final recoverableTimeout =
        error.errorMsg.contains('timeout') ||
        error.errorMsg.contains('no_match');
    if (_keepListening && !error.permanent && recoverableTimeout) {
      _handleSessionEnded();
      return;
    }

    _keepListening = false;
    _restartTimer?.cancel();
    _notifyListening(false);
    _onError?.call(SpeechToTextServiceException(error.errorMsg));
  }

  void _handleSoundLevel(double level) {
    if (level < _minimumSoundLevel) _minimumSoundLevel = level;
    if (level > _maximumSoundLevel) _maximumSoundLevel = level;
    final range = _maximumSoundLevel - _minimumSoundLevel;
    final normalized = range <= 0
        ? 0.35
        : ((level - _minimumSoundLevel) / range).clamp(0.0, 1.0);
    _onSoundLevelChanged?.call(normalized);
  }

  void _notifyListening(bool listening) {
    if (_notifiedListening == listening) return;
    _notifiedListening = listening;
    _onListeningChanged?.call(listening);
  }
}

class SpeechToTextServiceException implements Exception {
  const SpeechToTextServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
