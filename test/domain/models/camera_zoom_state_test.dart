import 'dart:async';

import 'package:amd_pet_frontend/domain/models/camera_zoom_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cover aspect ratio follows layout without camera state transitions',
    () {
      expect(
        cameraCoverAspectRatio(
          sensorAspectRatio: 16 / 9,
          isPortraitLayout: true,
        ),
        closeTo(9 / 16, 0.001),
      );
      expect(
        cameraCoverAspectRatio(
          sensorAspectRatio: 16 / 9,
          isPortraitLayout: false,
        ),
        closeTo(16 / 9, 0.001),
      );
    },
  );

  test('vertical drag zooms upward and clamps both directions', () {
    expect(
      zoomForVerticalDrag(
        baseZoom: 1,
        startY: 500,
        currentY: 320,
        minZoom: 0.5,
        maxZoom: 5,
      ),
      closeTo(2, 0.001),
    );
    expect(
      zoomForVerticalDrag(
        baseZoom: 1,
        startY: 500,
        currentY: -1000,
        minZoom: 0.5,
        maxZoom: 5,
      ),
      5,
    );
    expect(
      zoomForVerticalDrag(
        baseZoom: 1,
        startY: 500,
        currentY: 1500,
        minZoom: 0.5,
        maxZoom: 5,
      ),
      0.5,
    );
  });

  test(
    'zoom coordinator applies the active request and latest pending value',
    () async {
      final firstRequest = Completer<void>();
      final applied = <double>[];
      final coordinator = CameraZoomRequestCoordinator((zoom) async {
        applied.add(zoom);
        if (applied.length == 1) await firstRequest.future;
      });

      final first = coordinator.request(1.2);
      unawaited(coordinator.request(1.8));
      unawaited(coordinator.request(2.4));
      firstRequest.complete();
      await first;

      expect(applied, [1.2, 2.4]);
    },
  );
}
