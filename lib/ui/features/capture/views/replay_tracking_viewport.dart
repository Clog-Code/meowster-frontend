import 'package:flutter/material.dart';

import '../../../../domain/models/pet_tracking_sample.dart';
import '../../../core/pet_theme.dart';

class ReplayTrackingViewport extends StatelessWidget {
  const ReplayTrackingViewport({
    required this.media,
    required this.sourceSize,
    required this.normalizedBoundingBox,
    required this.label,
    super.key,
  });

  final Widget media;
  final Size sourceSize;
  final Rect? normalizedBoundingBox;
  final String label;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final outputSize = constraints.biggest;
        final box = normalizedBoundingBox;
        final frame = box == null || sourceSize.isEmpty || outputSize.isEmpty
            ? null
            : replayTrackingFrame(
                normalizedBoundingBox: box,
                sourceSize: sourceSize,
                outputSize: outputSize,
              );
        final transform = frame == null
            ? Matrix4.identity()
            : (Matrix4.identity()
                ..translateByDouble(
                  frame.translation.dx,
                  frame.translation.dy,
                  0,
                  1,
                )
                ..scaleByDouble(frame.scale, frame.scale, 1, 1));

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedContainer(
                key: const Key('replay-media-transform'),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                transform: transform,
                transformAlignment: Alignment.topLeft,
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox.fromSize(size: sourceSize, child: media),
                ),
              ),
              if (frame != null)
                Positioned.fromRect(
                  rect: frame.outputBoundingBox,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const Key('replay-tracking-box'),
                      decoration: BoxDecoration(
                        border: Border.all(color: PetTheme.aqua, width: 2.4),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Transform.translate(
                          offset: const Offset(0, -30),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xD9000000),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              child: Text(
                                label,
                                style: const TextStyle(
                                  color: PetTheme.aqua,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
