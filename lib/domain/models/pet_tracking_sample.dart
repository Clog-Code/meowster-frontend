import 'dart:ui';

import 'package:flutter/foundation.dart';

@immutable
class PetTrackingSample {
  const PetTrackingSample({
    required this.timestamp,
    required this.normalizedBoundingBox,
  });

  final Duration timestamp;
  final Rect normalizedBoundingBox;
}

PetTrackingSample? normalizedTrackingSample({
  required Rect boundingBox,
  required Size imageSize,
  required Duration timestamp,
}) {
  if (imageSize.isEmpty || boundingBox.isEmpty) return null;
  final normalized = Rect.fromLTRB(
    (boundingBox.left / imageSize.width).clamp(0.0, 1.0),
    (boundingBox.top / imageSize.height).clamp(0.0, 1.0),
    (boundingBox.right / imageSize.width).clamp(0.0, 1.0),
    (boundingBox.bottom / imageSize.height).clamp(0.0, 1.0),
  );
  if (normalized.isEmpty) return null;
  return PetTrackingSample(
    timestamp: timestamp,
    normalizedBoundingBox: normalized,
  );
}

List<PetTrackingSample> sanitizeTrackingSamples(
  Iterable<PetTrackingSample> samples, {
  Duration minimumSpacing = const Duration(milliseconds: 80),
}) {
  final sorted = samples.where((sample) {
    final box = sample.normalizedBoundingBox;
    return !box.isEmpty &&
        box.left >= 0 &&
        box.top >= 0 &&
        box.right <= 1 &&
        box.bottom <= 1;
  }).toList()..sort((left, right) => left.timestamp.compareTo(right.timestamp));
  final accepted = <PetTrackingSample>[];
  for (final sample in sorted) {
    if (accepted.isEmpty ||
        sample.timestamp - accepted.last.timestamp >= minimumSpacing) {
      accepted.add(sample);
    }
  }
  return List.unmodifiable(accepted);
}

PetTrackingSample? trackingSampleAt(
  List<PetTrackingSample> samples,
  Duration position, {
  Duration maxGap = const Duration(milliseconds: 1500),
}) {
  if (samples.isEmpty) return null;
  if (position <= samples.first.timestamp) {
    return samples.first.timestamp - position <= maxGap ? samples.first : null;
  }
  if (position >= samples.last.timestamp) {
    return position - samples.last.timestamp <= maxGap ? samples.last : null;
  }

  for (var index = 0; index < samples.length - 1; index += 1) {
    final before = samples[index];
    final after = samples[index + 1];
    if (position < before.timestamp || position > after.timestamp) continue;
    final gap = after.timestamp - before.timestamp;
    if (gap > maxGap || gap.inMicroseconds <= 0) return null;
    final elapsed = position - before.timestamp;
    final t = elapsed.inMicroseconds / gap.inMicroseconds;
    return PetTrackingSample(
      timestamp: position,
      normalizedBoundingBox: Rect.lerp(
        before.normalizedBoundingBox,
        after.normalizedBoundingBox,
        t,
      )!,
    );
  }
  return null;
}

@immutable
class ReplayTrackingFrame {
  const ReplayTrackingFrame({
    required this.scale,
    required this.translation,
    required this.outputBoundingBox,
  });

  final double scale;
  final Offset translation;
  final Rect outputBoundingBox;
}

ReplayTrackingFrame replayTrackingFrame({
  required Rect normalizedBoundingBox,
  required Size sourceSize,
  required Size outputSize,
  double targetWidthFraction = 0.45,
  double targetHeightFraction = 0.55,
  double maxScale = 2.2,
}) {
  final sourceRect = Rect.fromLTRB(
    normalizedBoundingBox.left * sourceSize.width,
    normalizedBoundingBox.top * sourceSize.height,
    normalizedBoundingBox.right * sourceSize.width,
    normalizedBoundingBox.bottom * sourceSize.height,
  );
  final outputRect = coverMappedRect(
    sourceRect: sourceRect,
    sourceSize: sourceSize,
    outputSize: outputSize,
  );
  if (outputRect.isEmpty) {
    return ReplayTrackingFrame(
      scale: 1,
      translation: Offset.zero,
      outputBoundingBox: outputRect,
    );
  }
  final desiredScale = <double>[
    outputSize.width * targetWidthFraction / outputRect.width,
    outputSize.height * targetHeightFraction / outputRect.height,
  ].reduce((left, right) => left < right ? left : right);
  final scale = desiredScale.clamp(1.0, maxScale).toDouble();
  final translation =
      outputSize.center(Offset.zero) - outputRect.center * scale;
  final transformedRect = Rect.fromCenter(
    center: outputRect.center * scale + translation,
    width: outputRect.width * scale,
    height: outputRect.height * scale,
  );
  return ReplayTrackingFrame(
    scale: scale,
    translation: translation,
    outputBoundingBox: transformedRect,
  );
}

Rect coverMappedRect({
  required Rect sourceRect,
  required Size sourceSize,
  required Size outputSize,
}) {
  if (sourceSize.isEmpty || outputSize.isEmpty) return Rect.zero;
  final widthScale = outputSize.width / sourceSize.width;
  final heightScale = outputSize.height / sourceSize.height;
  final scale = widthScale > heightScale ? widthScale : heightScale;
  final scaledSize = Size(sourceSize.width * scale, sourceSize.height * scale);
  final offset = Offset(
    (outputSize.width - scaledSize.width) / 2,
    (outputSize.height - scaledSize.height) / 2,
  );
  return Rect.fromLTRB(
    sourceRect.left * scale + offset.dx,
    sourceRect.top * scale + offset.dy,
    sourceRect.right * scale + offset.dx,
    sourceRect.bottom * scale + offset.dy,
  );
}
