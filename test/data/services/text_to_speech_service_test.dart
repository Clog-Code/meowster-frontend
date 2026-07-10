import 'package:amd_pet_frontend/data/services/text_to_speech_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Kokoro text preparation', () {
    test('strips markdown while retaining readable labels', () {
      const markdown =
          '# Care plan\n- Give **fresh water**. [Call the clinic](https://example.com).';

      expect(
        prepareSpeechText(markdown),
        'Care plan Give fresh water. Call the clinic.',
      );
    });

    test('splits long responses into bounded sentence chunks', () {
      final chunks = splitSpeechText(
        '${List.filled(18, 'A short sentence.').join(' ')} Final advice.',
        maxLength: 80,
      );

      expect(chunks, hasLength(greaterThan(1)));
      expect(chunks.every((chunk) => chunk.length <= 80), isTrue);
      expect(chunks.join(' '), endsWith('Final advice.'));
    });
  });

  test('buildTtsUri encodes text for the Kokoro GET endpoint', () {
    final uri = buildTtsUri(
      Uri.parse('http://192.168.0.101:8002'),
      'Food & water?',
    );

    expect(uri.path, '/tts');
    expect(uri.queryParameters['text'], 'Food & water?');
    expect(uri.toString(), contains('Food+%26+water%3F'));
  });
}
