import 'package:amd_pet_frontend/domain/models/pet_tracking_sample.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes a detected box and clamps it to the frame', () {
    final sample = normalizedTrackingSample(
      boundingBox: const Rect.fromLTRB(-10, 20, 120, 90),
      imageSize: const Size(100, 100),
      timestamp: const Duration(seconds: 1),
    );

    expect(sample, isNotNull);
    expect(sample!.normalizedBoundingBox, const Rect.fromLTRB(0, 0.2, 1, 0.9));
  });

  test('interpolates samples and rejects stale gaps', () {
    const samples = [
      PetTrackingSample(
        timestamp: Duration.zero,
        normalizedBoundingBox: Rect.fromLTWH(0.1, 0.2, 0.2, 0.3),
      ),
      PetTrackingSample(
        timestamp: Duration(seconds: 1),
        normalizedBoundingBox: Rect.fromLTWH(0.3, 0.4, 0.2, 0.3),
      ),
    ];

    final halfway = trackingSampleAt(
      samples,
      const Duration(milliseconds: 500),
    );
    expect(halfway!.normalizedBoundingBox.left, closeTo(0.2, 0.001));
    expect(halfway.normalizedBoundingBox.top, closeTo(0.3, 0.001));
    expect(trackingSampleAt(samples, const Duration(seconds: 3)), isNull);
  });

  test('sanitizes, orders, and deduplicates recording samples', () {
    final samples = sanitizeTrackingSamples([
      const PetTrackingSample(
        timestamp: Duration(milliseconds: 300),
        normalizedBoundingBox: Rect.fromLTWH(0.2, 0.2, 0.3, 0.3),
      ),
      const PetTrackingSample(
        timestamp: Duration(milliseconds: 100),
        normalizedBoundingBox: Rect.fromLTWH(0.1, 0.1, 0.3, 0.3),
      ),
      const PetTrackingSample(
        timestamp: Duration(milliseconds: 140),
        normalizedBoundingBox: Rect.fromLTWH(0.15, 0.1, 0.3, 0.3),
      ),
      const PetTrackingSample(
        timestamp: Duration(milliseconds: 500),
        normalizedBoundingBox: Rect.fromLTRB(-0.1, 0.1, 0.3, 0.4),
      ),
    ]);

    expect(samples.map((sample) => sample.timestamp), [
      const Duration(milliseconds: 100),
      const Duration(milliseconds: 300),
    ]);
  });

  test('auto-framing centers the pet and respects the zoom cap', () {
    final frame = replayTrackingFrame(
      normalizedBoundingBox: const Rect.fromLTWH(0.05, 0.2, 0.15, 0.2),
      sourceSize: const Size(1920, 1080),
      outputSize: const Size(390, 844),
    );

    expect(frame.scale, inInclusiveRange(1, 2.2));
    expect(frame.outputBoundingBox.center.dx, closeTo(195, 0.001));
    expect(frame.outputBoundingBox.center.dy, closeTo(422, 0.001));
  });
}
