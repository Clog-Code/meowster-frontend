import 'package:amd_pet_frontend/ui/features/capture/views/replay_tracking_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tracking viewport transforms media and displays its label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 390,
          height: 844,
          child: ReplayTrackingViewport(
            sourceSize: Size(1920, 1080),
            normalizedBoundingBox: Rect.fromLTWH(0.1, 0.2, 0.2, 0.25),
            label: 'CAT / NORMAL',
            media: ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('replay-tracking-box')), findsOneWidget);
    expect(find.text('CAT / NORMAL'), findsOneWidget);
    final container = tester.widget<AnimatedContainer>(
      find.byKey(const Key('replay-media-transform')),
    );
    expect(container.transform, isNot(equals(Matrix4.identity())));
  });
}
