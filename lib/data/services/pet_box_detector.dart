import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

class PetBoxCandidate {
  const PetBoxCandidate({
    required this.boundingBox,
    required this.imageSize,
    required this.label,
    required this.confidence,
    required this.isCat,
  });

  final Rect boundingBox;
  final Size imageSize;
  final String label;
  final double confidence;
  final bool isCat;

  double get area => boundingBox.width * boundingBox.height;
}

class PetBoxTracker {
  PetBoxTracker({this.staleAfter = const Duration(milliseconds: 1200)});

  final Duration staleAfter;
  PetBoxCandidate? _current;
  DateTime? _updatedAt;

  PetBoxCandidate? update(List<PetBoxCandidate> candidates, {DateTime? now}) {
    final selected = selectBestPetBox(candidates);
    if (selected != null) {
      _current = selected;
      _updatedAt = now ?? DateTime.now();
    }
    return current(now: now);
  }

  PetBoxCandidate? current({DateTime? now}) {
    final updatedAt = _updatedAt;
    if (_current == null || updatedAt == null) return null;
    final reference = now ?? DateTime.now();
    if (reference.difference(updatedAt) > staleAfter) return null;
    return _current;
  }

  void clear() {
    _current = null;
    _updatedAt = null;
  }
}

PetBoxCandidate? selectBestPetBox(List<PetBoxCandidate> candidates) {
  if (candidates.isEmpty) return null;
  final sorted = [...candidates]
    ..sort((left, right) {
      final leftScore = _petBoxScore(left);
      final rightScore = _petBoxScore(right);
      return rightScore.compareTo(leftScore);
    });
  return sorted.first;
}

double _petBoxScore(PetBoxCandidate candidate) {
  final catBonus = candidate.isCat ? 1000000000.0 : 0.0;
  return catBonus + candidate.confidence * 1000000.0 + candidate.area;
}

abstract class PetBoxDetector {
  Future<PetBoxCandidate?> detect(
    CameraImage image,
    CameraDescription camera, {
    required DeviceOrientation deviceOrientation,
  });

  Future<void> close();
}

class MlKitPetBoxDetector implements PetBoxDetector {
  MlKitPetBoxDetector({ObjectDetector? detector})
    : _detector =
          detector ??
          ObjectDetector(
            options: ObjectDetectorOptions(
              mode: DetectionMode.stream,
              classifyObjects: true,
              multipleObjects: true,
            ),
          );

  final ObjectDetector _detector;

  @override
  Future<PetBoxCandidate?> detect(
    CameraImage image,
    CameraDescription camera, {
    required DeviceOrientation deviceOrientation,
  }) async {
    final rotationDegrees = cameraImageRotationDegrees(
      sensorOrientation: camera.sensorOrientation,
      deviceOrientation: deviceOrientation,
      lensDirection: camera.lensDirection,
      isAndroid: Platform.isAndroid,
    );
    final inputImage = _inputImageFromCameraImage(
      image,
      rotationDegrees: rotationDegrees,
    );
    final objects = await _detector.processImage(inputImage);
    final rawImageSize = Size(image.width.toDouble(), image.height.toDouble());
    return selectBestPetBox(
      objects
          .map(
            (object) => _candidateFromObject(
              object,
              rawImageSize: rawImageSize,
              rotationDegrees: rotationDegrees,
              lensDirection: camera.lensDirection,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<void> close() => _detector.close();

  InputImage _inputImageFromCameraImage(
    CameraImage image, {
    required int rotationDegrees,
  }) {
    final format = _formatFromCameraImage(image);
    final expectedFormat = Platform.isAndroid
        ? InputImageFormat.nv21
        : InputImageFormat.bgra8888;
    if (format != expectedFormat || image.planes.length != 1) {
      throw StateError(
        'Unsupported camera frame: ${image.format.group.name}, '
        '${image.planes.length} plane(s).',
      );
    }

    final plane = image.planes.first;
    final supportedFormat = format!;
    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation:
          InputImageRotationValue.fromRawValue(rotationDegrees) ??
          InputImageRotation.rotation0deg,
      format: supportedFormat,
      bytesPerRow: plane.bytesPerRow,
    );
    return InputImage.fromBytes(bytes: plane.bytes, metadata: metadata);
  }

  InputImageFormat? _formatFromCameraImage(CameraImage image) {
    return switch (image.format.group) {
      ImageFormatGroup.nv21 => InputImageFormat.nv21,
      ImageFormatGroup.bgra8888 => InputImageFormat.bgra8888,
      _ => null,
    };
  }

  PetBoxCandidate _candidateFromObject(
    DetectedObject object, {
    required Size rawImageSize,
    required int rotationDegrees,
    required CameraLensDirection lensDirection,
  }) {
    final catLabel = object.labels
        .where((label) => label.text.toLowerCase().contains('cat'))
        .cast<Label?>()
        .firstWhere((label) => label != null, orElse: () => null);
    final bestLabel = [...object.labels]
      ..sort((left, right) => right.confidence.compareTo(left.confidence));
    final label = catLabel ?? (bestLabel.isEmpty ? null : bestLabel.first);
    final isCat = catLabel != null;
    final mapped = _normaliseBoundingBox(
      object.boundingBox,
      rawImageSize: rawImageSize,
      rotationDegrees: rotationDegrees,
      lensDirection: lensDirection,
    );
    return PetBoxCandidate(
      boundingBox: mapped.$1,
      imageSize: mapped.$2,
      label: isCat ? 'Cat' : 'Cat candidate',
      confidence: label?.confidence ?? 0,
      isCat: isCat,
    );
  }
}

int cameraImageRotationDegrees({
  required int sensorOrientation,
  required DeviceOrientation deviceOrientation,
  required CameraLensDirection lensDirection,
  required bool isAndroid,
}) {
  if (!isAndroid) return sensorOrientation;
  final deviceDegrees = switch (deviceOrientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };
  return lensDirection == CameraLensDirection.front
      ? (sensorOrientation + deviceDegrees) % 360
      : (sensorOrientation - deviceDegrees + 360) % 360;
}

(Rect, Size) _normaliseBoundingBox(
  Rect rect, {
  required Size rawImageSize,
  required int rotationDegrees,
  required CameraLensDirection lensDirection,
}) {
  if (!Platform.isAndroid) return (rect, rawImageSize);

  if (rotationDegrees == 90) {
    return (rect, Size(rawImageSize.height, rawImageSize.width));
  }
  if (rotationDegrees == 270) {
    final width = rawImageSize.height;
    return (
      Rect.fromLTRB(
        width - rect.right,
        rect.top,
        width - rect.left,
        rect.bottom,
      ),
      Size(rawImageSize.height, rawImageSize.width),
    );
  }
  if (lensDirection == CameraLensDirection.front) {
    return (
      Rect.fromLTRB(
        rawImageSize.width - rect.right,
        rect.top,
        rawImageSize.width - rect.left,
        rect.bottom,
      ),
      rawImageSize,
    );
  }
  return (rect, rawImageSize);
}
