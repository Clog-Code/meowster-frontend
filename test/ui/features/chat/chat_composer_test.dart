import 'dart:io';

import 'package:amd_pet_frontend/ui/core/pet_theme.dart';
import 'package:amd_pet_frontend/ui/features/chat/chat_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('photo attachment stays sharp in a 48px square', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _composer(controller: controller, attachmentPath: '/tmp/attachment.jpg'),
    );

    expect(find.byKey(const ValueKey('attachment-photo-thumbnail')), findsOne);
    expect(find.byKey(const ValueKey('blurred-video-thumbnail')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('attachment-thumbnail'))),
      const Size.square(48),
    );
    expect(find.text('Photo attached'), findsOne);
  });

  testWidgets('video path uses the thumbnail chip as a safe fallback', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final video = await _temporaryFile('attachment.mp4', const []);
    addTearDown(() => video.parent.delete(recursive: true));

    await tester.pumpWidget(
      _composer(controller: controller, attachmentPath: video.path),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('attachment-thumbnail-fallback')),
      findsOne,
    );
    expect(find.byIcon(Icons.videocam_outlined), findsOne);
    expect(find.text('Video attached'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('upload overlay and remove action stay above video fallback', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final video = await _temporaryFile('uploading.mov', const []);
    addTearDown(() => video.parent.delete(recursive: true));
    var removed = false;

    await tester.pumpWidget(
      _composer(
        controller: controller,
        attachmentPath: video.path,
        uploading: true,
        onRemove: () => removed = true,
      ),
    );
    await tester.pump();

    expect(find.text('Attaching video…'), findsOne);
    expect(find.byType(CircularProgressIndicator), findsOne);
    expect(find.byTooltip('Remove video'), findsOne);

    await tester.tap(find.byTooltip('Remove video'));
    expect(removed, isTrue);
  });

  testWidgets('replacing and removing a video releases preview state', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final first = await _temporaryFile('first.mp4', const []);
    final second = await _temporaryFile('second.webm', const []);
    addTearDown(() async {
      await first.parent.delete(recursive: true);
      await second.parent.delete(recursive: true);
    });

    await tester.pumpWidget(
      _composer(controller: controller, attachmentPath: first.path),
    );
    await tester.pump();
    await tester.pumpWidget(
      _composer(controller: controller, attachmentPath: second.path),
    );
    await tester.pump();
    await tester.pumpWidget(_composer(controller: controller));
    await tester.pump();

    expect(find.byKey(const ValueKey('attachment-thumbnail')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _composer({
  required TextEditingController controller,
  String? attachmentPath,
  bool uploading = false,
  VoidCallback? onRemove,
}) {
  return MaterialApp(
    theme: PetTheme.dark(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 390,
          child: ChatComposer(
            controller: controller,
            isSending: false,
            isListening: false,
            soundLevel: 0,
            onGallery: () {},
            onHoldStart: () {},
            onHoldEnd: () {},
            onTapStart: () {},
            onConfirmListening: () {},
            onCancelListening: () {},
            onSend: () {},
            onStop: () {},
            pendingImagePath: attachmentPath,
            isUploadingImage: uploading,
            onRemoveAttachment: onRemove,
          ),
        ),
      ),
    ),
  );
}

Future<File> _temporaryFile(String name, List<int> bytes) async {
  final directory = await Directory.systemTemp.createTemp('composer-preview-');
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(bytes);
  return file;
}
