import 'package:amd_pet_frontend/ui/features/capture/views/camera_preview_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('portrait preview uses stable cover geometry without rotation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 390,
            height: 844,
            child: CameraPreviewCover(
              sensorAspectRatio: 16 / 9,
              preview: ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );

    final source = tester.widget<SizedBox>(
      find.byKey(const Key('camera-preview-source')),
    );
    expect(source.width, closeTo(562.5, 0.001));
    expect(source.height, 1000);
    expect(find.byType(RotatedBox), findsNothing);

    await tester.pump();
    final unchanged = tester.widget<SizedBox>(
      find.byKey(const Key('camera-preview-source')),
    );
    expect(unchanged.width, source.width);
    expect(unchanged.height, source.height);
  });

  testWidgets('landscape preview uses the sensor aspect ratio', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 844,
            height: 390,
            child: CameraPreviewCover(
              sensorAspectRatio: 16 / 9,
              preview: ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );

    final source = tester.widget<SizedBox>(
      find.byKey(const Key('camera-preview-source')),
    );
    expect(source.width, closeTo(1777.78, 0.01));
    expect(source.height, 1000);
    expect(find.byType(RotatedBox), findsNothing);
  });
}
