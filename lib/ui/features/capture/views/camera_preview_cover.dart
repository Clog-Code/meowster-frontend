import 'package:flutter/material.dart';

import '../../../../domain/models/camera_zoom_state.dart';

class CameraPreviewCover extends StatelessWidget {
  const CameraPreviewCover({
    required this.sensorAspectRatio,
    required this.preview,
    super.key,
  });

  final double sensorAspectRatio;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isPortraitLayout = constraints.maxHeight >= constraints.maxWidth;
        final displayAspectRatio = cameraCoverAspectRatio(
          sensorAspectRatio: sensorAspectRatio,
          isPortraitLayout: isPortraitLayout,
        );
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              key: const Key('camera-preview-source'),
              width: displayAspectRatio * 1000,
              height: 1000,
              child: preview,
            ),
          ),
        );
      },
    );
  }
}
