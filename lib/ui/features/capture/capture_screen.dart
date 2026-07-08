import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../data/services/agent_stream_client.dart';
import '../../../domain/models/pet_capture_result.dart';
import '../../core/pet_theme.dart';
import '../chat/agent_chat_screen.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    required this.client,
    this.enableCamera = true,
    super.key,
  });

  final AgentStreamClient client;
  final bool enableCamera;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _picker = ImagePicker();
  CameraController? _cameraController;
  VideoPlayerController? _videoController;
  PetCaptureResult? _preview;
  Timer? _recordingTimer;
  bool _cameraLoading = true;
  bool _recording = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    _initialiseCamera();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _cameraController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initialiseCamera() async {
    if (!widget.enableCamera) {
      setState(() {
        _cameraLoading = false;
        _cameraError = 'Camera disabled in this environment.';
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('no_camera', 'No camera found on this device.');
      }
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _cameraLoading = false;
        _cameraError = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraLoading = false;
        _cameraError = _cameraMessage(error);
      });
    }
  }

  Future<void> _toggleRecording() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      _setDemoPreview();
      return;
    }

    if (_recording) {
      await _stopRecording();
      return;
    }

    try {
      await controller.startVideoRecording();
      setState(() => _recording = true);
      _recordingTimer?.cancel();
      _recordingTimer = Timer(const Duration(seconds: 10), _stopRecording);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = _cameraMessage(error));
    }
  }

  Future<void> _stopRecording() async {
    final controller = _cameraController;
    if (!_recording || controller == null) return;

    _recordingTimer?.cancel();
    try {
      final file = await controller.stopVideoRecording();
      await _setPreview(
        PetCaptureResult(
          kind: CaptureMediaKind.video,
          species: 'cat',
          emotion: 'curious',
          healthFlags: const ['normal posture'],
          sourceLabel: 'Captured video',
          path: file.path,
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = _cameraMessage(error));
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image == null) return;
      await _setPreview(
        PetCaptureResult(
          kind: CaptureMediaKind.image,
          species: 'cat',
          emotion: 'watchful',
          healthFlags: const ['needs review'],
          sourceLabel: 'Uploaded image',
          path: image.path,
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = _cameraMessage(error));
    }
  }

  Future<void> _setPreview(PetCaptureResult result) async {
    await _videoController?.dispose();
    VideoPlayerController? controller;
    if (result.kind == CaptureMediaKind.video && result.path != null) {
      controller = VideoPlayerController.file(File(result.path!));
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
    }
    if (!mounted) {
      await controller?.dispose();
      return;
    }
    setState(() {
      _preview = result;
      _videoController = controller;
      _cameraError = null;
    });
  }

  void _setDemoPreview() {
    _setPreview(
      const PetCaptureResult(
        kind: CaptureMediaKind.demo,
        species: 'cat',
        emotion: 'distress',
        healthFlags: ['limping', 'low appetite'],
        sourceLabel: 'Demo capture',
      ),
    );
  }

  void _retake() {
    _videoController?.dispose();
    setState(() {
      _preview = null;
      _videoController = null;
    });
  }

  void _askAgent() {
    final preview = _preview;
    if (preview == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            AgentChatScreen(client: widget.client, initialCapture: preview),
      ),
    );
  }

  String _cameraMessage(Object error) {
    if (error is MissingPluginException) {
      return 'Camera is unavailable in this runtime.';
    }
    if (error is CameraException) {
      return error.description ?? error.code;
    }
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (preview == null)
            _CameraBackdrop(
              controller: _cameraController,
              loading: _cameraLoading,
              error: _cameraError,
            )
          else
            _PreviewBackdrop(
              result: preview,
              videoController: _videoController,
            ),
          const _CaptureGradient(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                children: [
                  _CaptureTopBar(onDemo: _setDemoPreview),
                  const Spacer(),
                  _EditorialOverlay(result: preview),
                  const SizedBox(height: 28),
                  if (preview == null)
                    _CaptureControls(
                      recording: _recording,
                      onCapture: _toggleRecording,
                      onGallery: _pickImage,
                      onChat: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) =>
                                AgentChatScreen(client: widget.client),
                          ),
                        );
                      },
                    )
                  else
                    _PreviewActions(onRetake: _retake, onAskAgent: _askAgent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraBackdrop extends StatelessWidget {
  const _CameraBackdrop({
    required this.controller,
    required this.loading,
    required this.error,
  });

  final CameraController? controller;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final camera = controller;
    if (camera != null && camera.value.isInitialized) {
      return Center(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: camera.value.previewSize?.height ?? 1,
              height: camera.value.previewSize?.width ?? 1,
              child: CameraPreview(camera),
            ),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF111418),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const CircularProgressIndicator(color: PetTheme.aqua)
              else
                const Icon(
                  Icons.photo_camera_outlined,
                  color: PetTheme.ivory,
                  size: 48,
                ),
              const SizedBox(height: 18),
              Text(
                loading ? 'Opening pet camera' : 'Camera fallback ready',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: PetTheme.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewBackdrop extends StatelessWidget {
  const _PreviewBackdrop({required this.result, required this.videoController});

  final PetCaptureResult result;
  final VideoPlayerController? videoController;

  @override
  Widget build(BuildContext context) {
    if (result.kind == CaptureMediaKind.video &&
        videoController != null &&
        videoController!.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: videoController!.value.size.width,
          height: videoController!.value.size.height,
          child: VideoPlayer(videoController!),
        ),
      );
    }

    if (result.kind == CaptureMediaKind.image && result.path != null) {
      return Image.file(File(result.path!), fit: BoxFit.cover);
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF193338), Color(0xFF6E3328), Color(0xFF111418)],
        ),
      ),
    );
  }
}

class _CaptureGradient extends StatelessWidget {
  const _CaptureGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB0000000), Color(0x10000000), Color(0xE6000000)],
          stops: [0, 0.42, 1],
        ),
      ),
    );
  }
}

class _CaptureTopBar extends StatelessWidget {
  const _CaptureTopBar({required this.onDemo});

  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _StatusPill(label: 'Pet moment'),
        const Spacer(),
        IconButton(
          tooltip: 'Demo capture',
          onPressed: onDemo,
          icon: const Icon(Icons.auto_awesome, color: PetTheme.ivory),
        ),
      ],
    );
  }
}

class _EditorialOverlay extends StatelessWidget {
  const _EditorialOverlay({required this.result});

  final PetCaptureResult? result;

  @override
  Widget build(BuildContext context) {
    final preview = result;
    final tags = preview == null
        ? const ['CAT', 'MENTAL + PHYSICAL HEALTH']
        : [preview.species.toUpperCase(), preview.emotion.toUpperCase()];
    final title = preview == null
        ? 'Capture The Pet Moment'
        : 'Ready For Agent Review';
    final body = preview == null
        ? 'Record up to 10 seconds or upload a picture for the health agent.'
        : preview.healthFlags.join(' / ');

    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [for (final tag in tags) _StatusPill(label: tag)],
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 34,
            height: 1.05,
            fontWeight: FontWeight.w500,
            color: PetTheme.ivory,
          ),
        ),
        const SizedBox(height: 14),
        const SizedBox(
          width: 42,
          child: Divider(color: PetTheme.ivory, thickness: 1.2),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: PetTheme.ivory, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x33000000),
        border: Border.all(color: const Color(0x80FFFFFF)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(
            color: PetTheme.ivory,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _CaptureControls extends StatelessWidget {
  const _CaptureControls({
    required this.recording,
    required this.onCapture,
    required this.onGallery,
    required this.onChat,
  });

  final bool recording;
  final VoidCallback onCapture;
  final VoidCallback onGallery;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _RoundIconButton(
          tooltip: 'Upload picture',
          icon: Icons.photo_library_outlined,
          onPressed: onGallery,
        ),
        Semantics(
          button: true,
          label: recording ? 'Stop recording' : 'Record pet video',
          child: GestureDetector(
            onTap: onCapture,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: PetTheme.ivory, width: 4),
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: recording ? 34 : 58,
                  height: recording ? 34 : 58,
                  decoration: BoxDecoration(
                    color: recording ? PetTheme.coral : PetTheme.ivory,
                    borderRadius: BorderRadius.circular(recording ? 8 : 40),
                  ),
                ),
              ),
            ),
          ),
        ),
        _RoundIconButton(
          tooltip: 'Open agent chat',
          icon: Icons.chat_bubble_outline,
          onPressed: onChat,
        ),
      ],
    );
  }
}

class _PreviewActions extends StatelessWidget {
  const _PreviewActions({required this.onRetake, required this.onAskAgent});

  final VoidCallback onRetake;
  final VoidCallback onAskAgent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onRetake,
            icon: const Icon(Icons.refresh),
            label: const Text('Retake'),
            style: OutlinedButton.styleFrom(
              foregroundColor: PetTheme.ivory,
              side: const BorderSide(color: Color(0x80FFFFFF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: onAskAgent,
            icon: const Icon(Icons.send),
            label: const Text('Ask Agent'),
          ),
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: const Color(0x33000000),
        foregroundColor: PetTheme.ivory,
        fixedSize: const Size(52, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
