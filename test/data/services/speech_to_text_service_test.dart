import 'package:amd_pet_frontend/data/services/speech_to_text_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpeechTranscriptAccumulator', () {
    test('merges restarted sessions without duplicate final results', () {
      final transcript = SpeechTranscriptAccumulator();

      expect(transcript.update('My cat is', isFinal: false), 'My cat is');
      expect(
        transcript.update('My cat is limping', isFinal: true),
        'My cat is limping',
      );
      expect(transcript.completeSession(), 'My cat is limping');
      expect(
        transcript.update('after jumping', isFinal: true),
        'My cat is limping after jumping',
      );
      expect(
        transcript.update('after jumping', isFinal: true),
        'My cat is limping after jumping',
      );
    });

    test('explicit completion preserves the latest partial session', () {
      final transcript = SpeechTranscriptAccumulator();
      transcript.update('please check her paw', isFinal: false);

      expect(transcript.completeSession(), 'please check her paw');
    });
  });
}
