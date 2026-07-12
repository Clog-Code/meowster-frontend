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

class CameraZoomRequestCoordinator {
  CameraZoomRequestCoordinator(this._applyZoom);

  final Future<void> Function(double zoom) _applyZoom;
  double? _pendingZoom;
  bool _applying = false;

  Future<void> request(double zoom) async {
    _pendingZoom = zoom;
    if (_applying) return;
    _applying = true;
    try {
      while (_pendingZoom != null) {
        final nextZoom = _pendingZoom!;
        _pendingZoom = null;
        await _applyZoom(nextZoom);
      }
    } finally {
      _applying = false;
    }
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

double zoomForVerticalDrag({
  required double baseZoom,
  required double startY,
  required double currentY,
  required double minZoom,
  required double maxZoom,
  double pixelsPerDoubling = 180,
}) {
  final upwardDistance = startY - currentY;
  final multiplier = math.pow(2, upwardDistance / pixelsPerDoubling).toDouble();
  return clampZoom(baseZoom * multiplier, minZoom, maxZoom);
}

double cameraCoverAspectRatio({
  required double sensorAspectRatio,
  required bool isPortraitLayout,
}) {
  return isPortraitLayout ? 1 / sensorAspectRatio : sensorAspectRatio;
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
