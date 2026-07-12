import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../data/services/agent_stream_client.dart';
import '../../../data/services/pet_box_detector.dart';
import '../../../data/services/pet_streak_client.dart';
import '../../../data/services/text_to_speech_service.dart';
import '../../../data/services/visual_llm_client.dart';
import '../../../domain/models/camera_zoom_state.dart';
import '../../../domain/models/pet_capture_result.dart';
import '../../../domain/models/pet_streak_summary.dart';
import '../../core/pet_theme.dart';
import '../chat/agent_chat_screen.dart';
import '../streak/pet_moment_streak_screen.dart';
import '../../../data/services/local_moment_storage.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    required this.client,
    required this.streakClient,
    this.visualLlmClient = const DisabledVisualLlmClient(),
    this.petBoxDetector,
    this.textToSpeechService,
    this.autoReadPreferenceStore,
    this.enableCamera = true,
    this.openGalleryOnStart = false,
    super.key,
  });

  final AgentStreamClient client;
  final PetStreakClient streakClient;
  final VisualLlmClient visualLlmClient;
  final PetBoxDetector? petBoxDetector;
  final TextToSpeechService? textToSpeechService;
  final AutoReadPreferenceStore? autoReadPreferenceStore;
  final bool enableCamera;
  final bool openGalleryOnStart;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _picker = ImagePicker();
  late final PetBoxDetector _petBoxDetector;
  final _petBoxTracker = PetBoxTracker();
  CameraController? _cameraController;
  CameraDescription? _activeCamera;
  VideoPlayerController? _videoController;
  PetCaptureResult? _preview;
  PetBoxCandidate? _petBox;
  Timer? _recordingTimer;
  DateTime? _lastPetBoxDetectionAt;
  DateTime? _lastAutoTrackingAt;
  CameraZoomState _zoom = const CameraZoomState(min: 1, max: 1, current: 1);
  double _zoomAtScaleStart = 1;
  bool _cameraLoading = true;
  bool _recording = false;
  bool _analyzingImage = false;
  bool _analyzingVideo = false;
  bool _detectingPetBox = false;
  bool _trackingPetBox = false;
  bool _autoTracking = false;
  bool _savingMoment = false;
  bool _momentSaved = false;
  bool _disposing = false;
  String? _cameraError;
  String? _petTrackingIssue;
  late Future<PetStreakSummary> _streakFuture;

  @override
  void initState() {
    super.initState();
    _petBoxDetector = widget.petBoxDetector ?? MlKitPetBoxDetector();
    _streakFuture = _loadStreak();
    _initialiseCamera();
    if (widget.openGalleryOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickImage());
    }
  }

  @override
  void dispose() {
    _disposing = true;
    _recordingTimer?.cancel();
    unawaited(_stopPetTracking());
    unawaited(_petBoxDetector.close());
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
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _activeCamera = camera;
        _zoom = CameraZoomState(
          min: minZoom,
          max: maxZoom,
          current: clampZoom(1, minZoom, maxZoom),
        );
        _cameraLoading = false;
        _cameraError = null;
      });
      await _applyZoom(_zoom.current);
      await _startPetTracking();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraLoading = false;
        _cameraError = _cameraMessage(error);
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (_analyzingVideo) return;

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
      await _stopPetTracking();
      await controller.startVideoRecording(onAvailable: _handleCameraImage);
      setState(() {
        _recording = true;
        _trackingPetBox = true;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer(const Duration(seconds: 10), _stopRecording);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = _cameraMessage(error));
      unawaited(_startPetTracking());
    }
  }

  Future<void> _stopRecording() async {
    final controller = _cameraController;
    if (!_recording || controller == null) return;

    _recordingTimer?.cancel();
    try {
      final file = await controller.stopVideoRecording();
      if (mounted) {
        setState(() {
          _recording = false;
          _analyzingVideo = true;
          _cameraError = null;
        });
      }

      try {
        final prediction = await widget.visualLlmClient.predictVideoEmotion(
          File(file.path),
        );
        await _setPreview(
          PetCaptureResult(
            kind: CaptureMediaKind.video,
            species: 'cat',
            emotion: prediction.predictedEmotion,
            emotionConfidence: prediction.confidence,
            emotionProbabilities: prediction.detailBreakdown,
            healthFlags: const [],
            sourceLabel: 'Captured video',
            path: file.path,
          ),
        );
      } on Object catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Video emotion check unavailable. Using review mode instead. ${_friendlyVisualError(error)}',
            ),
          ),
        );
        await _setPreview(
          PetCaptureResult(
            kind: CaptureMediaKind.video,
            species: 'cat',
            emotion: 'curious',
            healthFlags: const ['needs review'],
            sourceLabel: 'Captured video',
            path: file.path,
          ),
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = _cameraMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _recording = false;
          _analyzingVideo = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image == null) return;

      if (mounted) {
        setState(() {
          _analyzingImage = true;
          _cameraError = null;
        });
      }

      try {
        final prediction = await widget.visualLlmClient.predictImageEmotion(
          File(image.path),
        );
        await _setPreview(
          PetCaptureResult(
            kind: CaptureMediaKind.image,
            species: 'cat',
            emotion: prediction.predictedEmotion,
            emotionConfidence: prediction.confidence,
            emotionProbabilities: prediction.detailBreakdown,
            healthFlags: const [],
            sourceLabel: 'Uploaded image',
            path: image.path,
          ),
        );
      } on Object catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Visual emotion check unavailable. Using review mode instead. ${_friendlyVisualError(error)}',
            ),
          ),
        );
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
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = _cameraMessage(error));
    } finally {
      if (mounted) setState(() => _analyzingImage = false);
    }
  }

  Future<void> _setPreview(PetCaptureResult result) async {
    await _stopPetTracking();
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
      _momentSaved = false;
    });
  }

  Future<PetStreakSummary> _loadStreak() {
    return widget.streakClient.fetchStreakSummary();
  }

  void _refreshStreak() {
    if (!mounted) return;
    setState(() {
      _streakFuture = _loadStreak();
    });
  }

  Future<void> _recordPetMoment(PetCaptureResult result) async {
    await widget.client.streamAgent(
      path: '/perception',
      payload: result.toPerceptionPayload(
        'streak-clock-in-${DateTime.now().millisecondsSinceEpoch}',
      ),
      onEvent: (_) {},
    );
    _refreshStreak();
  }

  void _setDemoPreview() {
    unawaited(
      _setPreview(
        const PetCaptureResult(
          kind: CaptureMediaKind.demo,
          species: 'cat',
          emotion: 'distress',
          healthFlags: ['limping', 'low appetite'],
          sourceLabel: 'Demo capture',
        ),
      ),
    );
  }

  void _retake() {
    _videoController?.dispose();
    setState(() {
      _preview = null;
      _videoController = null;
      _momentSaved = false;
      _savingMoment = false;
    });
    unawaited(_startPetTracking());
  }

  Future<void> _saveMoment() async {
      final preview = _preview;
      if (preview == null || _savingMoment || _momentSaved) return;
      setState(() => _savingMoment = true);
      try {
        if (preview.path != null) {
          await LocalMomentStorage.instance.saveMoment(
            sourcePath: preview.path!,
            isVideo: preview.kind == CaptureMediaKind.video,
          );
        }
        await _recordPetMoment(preview);
        if (!mounted) return;
        setState(() {
          _savingMoment = false;
          _momentSaved = true;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Moment saved.')));
      } on Object catch (error) {
        if (!mounted) return;
        setState(() => _savingMoment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not save moment. ${error.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    }

  void _askAgent() {
    final preview = _preview;
    if (preview == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AgentChatScreen(
          client: widget.client,
          streakClient: widget.streakClient,
          visualLlmClient: widget.visualLlmClient,
          textToSpeechService: widget.textToSpeechService,
          autoReadPreferenceStore: widget.autoReadPreferenceStore,
          initialCapture: preview,
        ),
      ),
    );
  }

  String _friendlyVisualError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    if (text.contains('Connection refused') ||
        text.contains('Visual LLM client is not configured')) {
      return 'Start the visual service and pass VISUAL_MODEL_BASE_URL to enable it.';
    }
    return text;
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

  Future<void> _startPetTracking() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isStreamingImages ||
        _recording ||
        _preview != null) {
      return;
    }
    try {
      await controller.startImageStream(_handleCameraImage);
      if (mounted) {
        setState(() {
          _trackingPetBox = true;
          _petTrackingIssue = null;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _trackingPetBox = false;
          _petTrackingIssue = _friendlyTrackingError(error);
        });
      }
    }
  }

  Future<void> _stopPetTracking() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isStreamingImages) {
      if (mounted && !_disposing) setState(() => _trackingPetBox = false);
      return;
    }
    try {
      await controller.stopImageStream();
    } on Object {
      // Tracking is best effort and should never block capture.
    } finally {
      if (mounted && !_disposing) {
        setState(() {
          _trackingPetBox = false;
          _detectingPetBox = false;
          _petBox = null;
        });
      }
    }
  }

  void _handleCameraImage(CameraImage image) {
    final camera = _activeCamera;
    if (camera == null || _detectingPetBox || _preview != null) {
      return;
    }
    final now = DateTime.now();
    final lastDetection = _lastPetBoxDetectionAt;
    if (lastDetection != null &&
        now.difference(lastDetection) < const Duration(milliseconds: 450)) {
      final current = _petBoxTracker.current(now: now);
      if (current == null && _petBox != null && mounted) {
        setState(() => _petBox = null);
      }
      return;
    }

    _lastPetBoxDetectionAt = now;
    _detectingPetBox = true;
    unawaited(() async {
      try {
        final controller = _cameraController;
        if (controller == null) return;
        final detected = await _petBoxDetector.detect(
          image,
          camera,
          deviceOrientation: controller.value.deviceOrientation,
        );
        final current = detected == null
            ? _petBoxTracker.current(now: DateTime.now())
            : _petBoxTracker.update([detected], now: DateTime.now());
        if (mounted) {
          setState(() {
            _petBox = current;
            _petTrackingIssue = null;
          });
        }
        if (detected != null && _autoTracking) {
          _applyAutoTracking(detected);
        }
      } on Object catch (error) {
        if (mounted) {
          setState(() {
            _petBox = null;
            _petTrackingIssue = _friendlyTrackingError(error);
          });
        }
      } finally {
        _detectingPetBox = false;
      }
    }());
  }

  Future<void> _applyZoom(double value) async {
    final controller = _cameraController;
    final nextZoom = clampZoom(value, _zoom.min, _zoom.max);
    if (!mounted) return;
    setState(() => _zoom = _zoom.copyWith(current: nextZoom));
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setZoomLevel(nextZoom);
    } on Object {
      // Some simulator/device cameras report zoom ranges they cannot apply.
    }
  }

  void _toggleAutoTracking() {
    setState(() {
      _autoTracking = !_autoTracking;
      _lastAutoTrackingAt = null;
    });
  }

  void _applyAutoTracking(PetBoxCandidate candidate) {
    final now = DateTime.now();
    final lastUpdate = _lastAutoTrackingAt;
    if (lastUpdate != null &&
        now.difference(lastUpdate) < const Duration(milliseconds: 550)) {
      return;
    }
    _lastAutoTrackingAt = now;

    final imageArea = candidate.imageSize.width * candidate.imageSize.height;
    final boxAreaFraction = imageArea <= 0 ? 0.0 : candidate.area / imageArea;
    final nextZoom = autoTrackingZoom(
      currentZoom: _zoom.current,
      boxAreaFraction: boxAreaFraction,
      minZoom: _zoom.min,
      maxZoom: _zoom.max,
    );
    if ((nextZoom - _zoom.current).abs() >= 0.03) {
      unawaited(_applyZoom(nextZoom));
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    final center = candidate.boundingBox.center;
    final point = Offset(
      (center.dx / candidate.imageSize.width).clamp(0.0, 1.0),
      (center.dy / candidate.imageSize.height).clamp(0.0, 1.0),
    );
    unawaited(controller.setFocusPoint(point));
    unawaited(controller.setExposurePoint(point));
  }

  String _friendlyTrackingError(Object error) {
    final text = error.toString().replaceFirst('Bad state: ', '');
    if (text.contains('Unsupported camera frame')) return text;
    return 'Pet tracking unavailable';
  }

  void _onPreviewScaleStart(ScaleStartDetails details) {
    _zoomAtScaleStart = _zoom.current;
  }

  void _onPreviewScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) return;
    if (_autoTracking) setState(() => _autoTracking = false);
    unawaited(
      _applyZoom(
        zoomForScale(
          baseZoom: _zoomAtScaleStart,
          scale: details.scale,
          minZoom: _zoom.min,
          maxZoom: _zoom.max,
        ),
      ),
    );
  }

  void _applyManualZoom(double value) {
    if (_autoTracking) setState(() => _autoTracking = false);
    unawaited(_applyZoom(value));
  }

  void _onPreviewTap(Offset localPosition, Size previewSize) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    final point = Offset(
      (localPosition.dx / previewSize.width).clamp(0.0, 1.0),
      (localPosition.dy / previewSize.height).clamp(0.0, 1.0),
    );
    unawaited(controller.setFocusPoint(point));
    unawaited(controller.setExposurePoint(point));
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
              petBox: _petBox,
              tracking: _trackingPetBox,
              trackingIssue: _petTrackingIssue,
              autoTracking: _autoTracking,
              onScaleStart: _onPreviewScaleStart,
              onScaleUpdate: _onPreviewScaleUpdate,
              onTapPreview: _onPreviewTap,
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
                  _CaptureTopBar(
                    streakFuture: _streakFuture,
                    onOpenStreak: _openStreakCalendar,
                    onDemo: _setDemoPreview,
                  ),
                  const Spacer(),
                  _EditorialOverlay(result: preview),
                  const SizedBox(height: 28),
                  if (preview == null)
                    Column(
                      children: [
                        _ZoomControl(
                          zoom: _zoom,
                          autoTracking: _autoTracking,
                          enabled:
                              _cameraController?.value.isInitialized ?? false,
                          onChanged: _applyManualZoom,
                          onToggleTracking: _toggleAutoTracking,
                        ),
                        const SizedBox(height: 14),
                        _CaptureControls(
                          recording: _recording,
                          analyzingImage: _analyzingImage,
                          analyzingVideo: _analyzingVideo,
                          onCapture: _toggleRecording,
                          onGallery: _pickImage,
                          onChat: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) => AgentChatScreen(
                                  client: widget.client,
                                  streakClient: widget.streakClient,
                                  visualLlmClient: widget.visualLlmClient,
                                  textToSpeechService:
                                      widget.textToSpeechService,
                                  autoReadPreferenceStore:
                                      widget.autoReadPreferenceStore,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    )
                  else
                    _PreviewActions(
                      saved: _momentSaved,
                      saving: _savingMoment,
                      onRetake: _retake,
                      onSave: _saveMoment,
                      onAskAgent: _askAgent,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openStreakCalendar() {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (context) =>
                PetMomentStreakScreen(streakClient: widget.streakClient),
          ),
        )
        .then((_) => _refreshStreak());
  }
}

class _CameraBackdrop extends StatelessWidget {
  const _CameraBackdrop({
    required this.controller,
    required this.loading,
    required this.error,
    required this.petBox,
    required this.tracking,
    required this.trackingIssue,
    required this.autoTracking,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onTapPreview,
  });

  final CameraController? controller;
  final bool loading;
  final String? error;
  final PetBoxCandidate? petBox;
  final bool tracking;
  final String? trackingIssue;
  final bool autoTracking;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;
  final void Function(Offset localPosition, Size previewSize) onTapPreview;

  @override
  Widget build(BuildContext context) {
    final camera = controller;
    if (camera != null && camera.value.isInitialized) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final previewSize = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: onScaleStart,
            onScaleUpdate: onScaleUpdate,
            onTapUp: (details) =>
                onTapPreview(details.localPosition, previewSize),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
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
                ),
                if (petBox != null)
                  CustomPaint(painter: _PetBoxPainter(candidate: petBox!)),
                if (tracking || trackingIssue != null)
                  Positioned(
                    left: 20,
                    top: 88,
                    child: _StatusPill(
                      label:
                          trackingIssue ??
                          (petBox == null
                              ? 'SCANNING FOR PET'
                              : autoTracking
                              ? 'AUTO TRACKING'
                              : 'PET FOUND'),
                    ),
                  ),
              ],
            ),
          );
        },
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

class _PetBoxPainter extends CustomPainter {
  const _PetBoxPainter({required this.candidate});

  final PetBoxCandidate candidate;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = _coverMappedRect(
      sourceRect: candidate.boundingBox,
      sourceSize: candidate.imageSize,
      outputSize: size,
    );
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = candidate.isCat ? PetTheme.aqua : PetTheme.warning;
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xAA000000);
    final labelStyle = TextStyle(
      color: candidate.isCat ? PetTheme.aqua : PetTheme.warning,
      fontSize: 12,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      borderPaint,
    );

    final label = candidate.confidence > 0
        ? '${candidate.label} ${(candidate.confidence * 100).round()}%'
        : candidate.label;
    final textPainter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width - 32);
    final labelRect = Rect.fromLTWH(
      rect.left,
      (rect.top - textPainter.height - 8).clamp(12.0, size.height - 32),
      textPainter.width + 16,
      textPainter.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(8)),
      fillPaint,
    );
    textPainter.paint(canvas, Offset(labelRect.left + 8, labelRect.top + 4));
  }

  @override
  bool shouldRepaint(covariant _PetBoxPainter oldDelegate) {
    return oldDelegate.candidate != candidate;
  }
}

Rect _coverMappedRect({
  required Rect sourceRect,
  required Size sourceSize,
  required Size outputSize,
}) {
  if (sourceSize.isEmpty || outputSize.isEmpty) return Rect.zero;
  final scale =
      outputSize.width / sourceSize.width >
          outputSize.height / sourceSize.height
      ? outputSize.width / sourceSize.width
      : outputSize.height / sourceSize.height;
  final scaledSize = Size(sourceSize.width * scale, sourceSize.height * scale);
  final dx = (outputSize.width - scaledSize.width) / 2;
  final dy = (outputSize.height - scaledSize.height) / 2;
  return Rect.fromLTRB(
    sourceRect.left * scale + dx,
    sourceRect.top * scale + dy,
    sourceRect.right * scale + dx,
    sourceRect.bottom * scale + dy,
  );
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
  const _CaptureTopBar({
    required this.streakFuture,
    required this.onOpenStreak,
    required this.onDemo,
  });

  final Future<PetStreakSummary> streakFuture;
  final VoidCallback onOpenStreak;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PetMomentStreakPill(
          streakFuture: streakFuture,
          onPressed: onOpenStreak,
        ),
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

class _PetMomentStreakPill extends StatelessWidget {
  const _PetMomentStreakPill({
    required this.streakFuture,
    required this.onPressed,
  });

  final Future<PetStreakSummary> streakFuture;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PetStreakSummary>(
      future: streakFuture,
      builder: (context, snapshot) {
        final streak = snapshot.hasData ? snapshot.data!.currentStreak : 0;
        return Tooltip(
          message: 'Open pet moment streak calendar',
          child: Semantics(
            button: true,
            label: 'Open pet moment streak calendar',
            child: GestureDetector(
              onTap: onPressed,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x33000000),
                  border: Border.all(color: const Color(0x80FFFFFF)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Pet moment',
                        style: TextStyle(
                          color: PetTheme.ivory,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _IgnitingFireIcon(active: streak > 0),
                      const SizedBox(width: 2),
                      Text(
                        '$streak',
                        style: const TextStyle(
                          color: PetTheme.ivory,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IgnitingFireIcon extends StatefulWidget {
  const _IgnitingFireIcon({required this.active});

  final bool active;

  @override
  State<_IgnitingFireIcon> createState() => _IgnitingFireIconState();
}

class _IgnitingFireIconState extends State<_IgnitingFireIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    );
    if (widget.active) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _IgnitingFireIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller
        ..value = 0
        ..forward();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return const Icon(
        Icons.local_fire_department,
        color: PetTheme.muted,
        size: 15,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = 0.82 + (_controller.value * 0.32);
        return SizedBox(
          width: 18,
          height: 18,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: 0.18 + (_controller.value * 0.24),
                child: Transform.scale(
                  scale: pulse,
                  child: const Icon(
                    Icons.local_fire_department,
                    color: PetTheme.warning,
                    size: 18,
                  ),
                ),
              ),
              Transform.scale(
                scale: 0.92 + (_controller.value * 0.12),
                child: const Icon(
                  Icons.local_fire_department,
                  color: PetTheme.coral,
                  size: 15,
                ),
              ),
            ],
          ),
        );
      },
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
        : const ['READY FOR AGENT REVIEW'];
    final title = preview == null
        ? 'Capture The Pet Moment'
        : '${preview.species.toUpperCase()} / ${preview.emotion.toUpperCase()}';
    final body = preview == null
        ? 'Record up to 10 seconds or upload a picture for the health agent.'
        : preview.emotionConfidence == null
        ? 'Emotion estimate ready to save or review.'
        : 'Emotion confidence ${(preview.emotionConfidence! * 100).round()}%';

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

class _ZoomControl extends StatelessWidget {
  const _ZoomControl({
    required this.zoom,
    required this.autoTracking,
    required this.enabled,
    required this.onChanged,
    required this.onToggleTracking,
  });

  final CameraZoomState zoom;
  final bool autoTracking;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final VoidCallback onToggleTracking;

  @override
  Widget build(BuildContext context) {
    final canZoom = enabled && zoom.max > zoom.min;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x33000000),
        border: Border.all(color: const Color(0x66FFFFFF)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.zoom_in, color: PetTheme.ivory, size: 18),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              child: Text(
                '${zoom.current.toStringAsFixed(1)}x',
                style: const TextStyle(
                  color: PetTheme.ivory,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
            Expanded(
              child: Slider(
                value: clampZoom(zoom.current, zoom.min, zoom.max),
                min: zoom.min,
                max: zoom.max <= zoom.min ? zoom.min + 0.1 : zoom.max,
                divisions: canZoom ? 20 : null,
                onChanged: canZoom ? onChanged : null,
              ),
            ),
            Text(
              '${zoom.max.toStringAsFixed(1)}x',
              style: const TextStyle(color: PetTheme.muted, fontSize: 12),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: autoTracking
                  ? 'Stop automatic pet tracking'
                  : 'Start automatic pet tracking',
              onPressed: enabled ? onToggleTracking : null,
              icon: Icon(
                Icons.center_focus_strong,
                color: autoTracking ? Colors.black : PetTheme.ivory,
              ),
              style: IconButton.styleFrom(
                backgroundColor: autoTracking
                    ? PetTheme.aqua
                    : const Color(0x33000000),
                fixedSize: const Size(40, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptureControls extends StatelessWidget {
  const _CaptureControls({
    required this.recording,
    required this.analyzingImage,
    required this.analyzingVideo,
    required this.onCapture,
    required this.onGallery,
    required this.onChat,
  });

  final bool recording;
  final bool analyzingImage;
  final bool analyzingVideo;
  final VoidCallback onCapture;
  final VoidCallback onGallery;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _RoundIconButton(
          tooltip: analyzingImage ? 'Checking image emotion' : 'Upload picture',
          icon: analyzingImage
              ? Icons.hourglass_top
              : Icons.photo_library_outlined,
          onPressed: analyzingImage ? null : onGallery,
        ),
        Semantics(
          button: true,
          label: analyzingVideo
              ? 'Checking video emotion'
              : recording
              ? 'Stop recording'
              : 'Record pet video',
          child: GestureDetector(
            onTap: analyzingVideo ? null : onCapture,
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
                    color: analyzingVideo
                        ? PetTheme.warning
                        : recording
                        ? PetTheme.coral
                        : PetTheme.ivory,
                    borderRadius: BorderRadius.circular(recording ? 8 : 40),
                  ),
                  child: analyzingVideo
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : null,
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
  const _PreviewActions({
    required this.saved,
    required this.saving,
    required this.onRetake,
    required this.onSave,
    required this.onAskAgent,
  });

  final bool saved;
  final bool saving;
  final VoidCallback onRetake;
  final VoidCallback onSave;
  final VoidCallback onAskAgent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: onRetake,
            icon: const Icon(Icons.refresh),
            label: const Text('Retake'),
            style: TextButton.styleFrom(
              foregroundColor: PetTheme.ivory,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: saved || saving ? null : onSave,
                icon: saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(saved ? Icons.check : Icons.bookmark_add_outlined),
                label: Text(saved ? 'Saved' : 'Save Moment'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PetTheme.ivory,
                  disabledForegroundColor: PetTheme.sage,
                  side: BorderSide(
                    color: saved ? PetTheme.sage : const Color(0x80FFFFFF),
                  ),
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
  final VoidCallback? onPressed;

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
