import 'dart:math' as math;

class CameraZoomState {
  const CameraZoomState({
    required this.min,
    required this.max,
    required this.current,
  });

  final double min;
  final double max;
  final double current;

  CameraZoomState copyWith({double? min, double? max, double? current}) {
    return CameraZoomState(
      min: min ?? this.min,
      max: max ?? this.max,
      current: current ?? this.current,
    );
  }
}

double clampZoom(double value, double min, double max) {
  if (max <= min) return min;
  return value.clamp(min, max).toDouble();
}

double zoomForScale({
  required double baseZoom,
  required double scale,
  required double minZoom,
  required double maxZoom,
}) {
  return clampZoom(baseZoom * scale, minZoom, maxZoom);
}

double autoTrackingZoom({
  required double currentZoom,
  required double boxAreaFraction,
  required double minZoom,
  required double maxZoom,
  double targetAreaFraction = 0.28,
  double smoothing = 0.22,
  double deadband = 0.04,
  double maxAutoZoom = 3,
}) {
  if (boxAreaFraction <= 0) return currentZoom;
  if ((boxAreaFraction - targetAreaFraction).abs() <= deadband) {
    return currentZoom;
  }
  final areaRatio = (targetAreaFraction / boxAreaFraction).clamp(0.25, 4.0);
  final desired = currentZoom * math.sqrt(areaRatio);
  final upperBound = maxZoom < maxAutoZoom ? maxZoom : maxAutoZoom;
  final clamped = clampZoom(desired, minZoom, upperBound);
  return clampZoom(
    currentZoom + (clamped - currentZoom) * smoothing,
    minZoom,
    upperBound,
  );
}
