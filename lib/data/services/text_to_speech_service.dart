import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class TextToSpeechService {
  Future<void> speak(String text);

  Future<void> stop();

  Future<void> dispose();
}

class KokoroTextToSpeechService implements TextToSpeechService {
  KokoroTextToSpeechService({required this.baseUri, AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  factory KokoroTextToSpeechService.fromEnvironment() {
    const configured = String.fromEnvironment(
      'TTS_BASE_URL',
      defaultValue: 'http://localhost:8002',
    );
    return KokoroTextToSpeechService(baseUri: Uri.parse(configured));
  }

  final Uri baseUri;
  final AudioPlayer _player;
  Completer<void>? _cancelWaiter;
  int _playbackToken = 0;
  bool _disposed = false;

  @override
  Future<void> speak(String text) async {
    if (_disposed) {
      throw const TextToSpeechException('Text-to-speech player is closed.');
    }
    final chunks = splitSpeechText(text);
    if (chunks.isEmpty) return;

    await stop();
    final token = _playbackToken;
    for (final chunk in chunks) {
      if (token != _playbackToken || _disposed) return;
      await _playChunk(chunk, token);
    }
  }

  Future<void> _playChunk(String chunk, int token) async {
    final completed = Completer<void>();
    final cancelled = Completer<void>();
    _cancelWaiter = cancelled;
    final subscription = _player.onPlayerComplete.listen((_) {
      if (!completed.isCompleted) completed.complete();
    });
    try {
      await _player.play(UrlSource(buildTtsUri(baseUri, chunk).toString()));
      await Future.any([completed.future, cancelled.future]);
    } on Object catch (error) {
      throw TextToSpeechException('Could not play Kokoro audio: $error');
    } finally {
      await subscription.cancel();
      if (identical(_cancelWaiter, cancelled)) _cancelWaiter = null;
    }
    if (token != _playbackToken) return;
  }

  @override
  Future<void> stop() async {
    _playbackToken += 1;
    final waiter = _cancelWaiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    if (!_disposed) await _player.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _player.dispose();
  }
}

abstract class AutoReadPreferenceStore {
  Future<bool> readEnabled();

  Future<void> writeEnabled(bool enabled);
}

class SharedPreferencesAutoReadStore implements AutoReadPreferenceStore {
  SharedPreferencesAutoReadStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const preferenceKey = 'agent_auto_read_enabled';
  final SharedPreferencesAsync _preferences;

  @override
  Future<bool> readEnabled() async {
    return await _preferences.getBool(preferenceKey) ?? true;
  }

  @override
  Future<void> writeEnabled(bool enabled) {
    return _preferences.setBool(preferenceKey, enabled);
  }
}

Uri buildTtsUri(Uri baseUri, String text) {
  final basePath = baseUri.path.endsWith('/')
      ? '${baseUri.path}tts'
      : '${baseUri.path}/tts';
  return baseUri.replace(
    path: basePath.replaceAll('//', '/'),
    queryParameters: {'text': text},
  );
}

String prepareSpeechText(String markdown) {
  return markdown
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAllMapped(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (match) => match[1]!)
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (match) => match[1]!)
      .replaceAllMapped(RegExp(r'`([^`]*)`'), (match) => match[1]!)
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*(?:[-*+] |\d+\.\s+|>\s*)', multiLine: true), '')
      .replaceAll(RegExp(r'[*_~]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

List<String> splitSpeechText(String markdown, {int maxLength = 600}) {
  final text = prepareSpeechText(markdown);
  if (text.isEmpty) return const [];
  if (text.length <= maxLength) return [text];

  final sentences = RegExp(r'[^.!?]+(?:[.!?]+|$)')
      .allMatches(text)
      .map((match) => match.group(0)!.trim())
      .where((sentence) => sentence.isNotEmpty);
  final chunks = <String>[];
  var current = '';

  void flush() {
    if (current.isEmpty) return;
    chunks.add(current);
    current = '';
  }

  for (final sentence in sentences) {
    if (sentence.length > maxLength) {
      flush();
      var wordChunk = '';
      for (final word in sentence.split(RegExp(r'\s+'))) {
        final candidate = wordChunk.isEmpty ? word : '$wordChunk $word';
        if (candidate.length > maxLength && wordChunk.isNotEmpty) {
          chunks.add(wordChunk);
          wordChunk = word;
        } else {
          wordChunk = candidate;
        }
      }
      if (wordChunk.isNotEmpty) chunks.add(wordChunk);
      continue;
    }

    final candidate = current.isEmpty ? sentence : '$current $sentence';
    if (candidate.length > maxLength) flush();
    current = current.isEmpty ? sentence : '$current $sentence';
  }
  flush();
  return chunks;
}

class TextToSpeechException implements Exception {
  const TextToSpeechException(this.message);

  final String message;

  @override
  String toString() => message;
}
