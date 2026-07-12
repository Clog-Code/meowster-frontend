import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../data/services/agent_stream_client.dart';
import '../../../data/services/pet_streak_client.dart';
import '../../../data/services/text_to_speech_service.dart';
import '../../../data/services/visual_llm_client.dart';
import '../../../domain/models/camera_zoom_state.dart';
import '../../../domain/models/pet_capture_result.dart';
import '../../../domain/models/pet_streak_summary.dart';
import '../../core/pet_theme.dart';
import '../chat/agent_chat_screen.dart';
import '../streak/pet_moment_streak_screen.dart';
import 'view_models/capture_view_model.dart';
import 'views/camera_preview_cover.dart';
import '../../../data/services/local_moment_storage.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    required this.client,
    required this.streakClient,
    required this.petId,
    required this.petName,
    this.visualLlmClient = const DisabledVisualLlmClient(),
    this.textToSpeechService,
    this.autoReadPreferenceStore,
    this.enableCamera = true,
    this.openGalleryOnStart = false,
    super.key,
  });

  final AgentStreamClient client;
  final PetStreakClient streakClient;
  final String petId;
  final String petName;
  final VisualLlmClient visualLlmClient;
  final TextToSpeechService? textToSpeechService;
  final AutoReadPreferenceStore? autoReadPreferenceStore;
  final bool enableCamera;
  final bool openGalleryOnStart;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with SingleTickerProviderStateMixin {
  static const String _fallbackPreviewAsset =
      'assets/videos/cat-preview/cat-preview-1.mp4';
  static const double _maxUserZoom = 5;

  final _picker = ImagePicker();
  CameraController? _cameraController;
  VideoPlayerController? _videoController;
  PetCaptureResult? _preview;
  Timer? _recordingTimer;
  Timer? _instructionPulseTimer;
  Timer? _instructionReturnTimer;
  CameraZoomState _zoom = const CameraZoomState(min: 1, max: 1, current: 1);
  double _zoomAtScaleStart = 1;
  double _shutterZoomStartY = 0;
  double _shutterZoomAtStart = 1;
  CameraZoomRequestCoordinator? _zoomRequestCoordinator;
  bool _cameraLoading = true;
  bool _recording = false;
  bool _recordGestureActive = false;
  bool _analyzingImage = false;
  bool _analyzingVideo = false;
  bool _savingMoment = false;
  bool _momentSaved = false;
  bool _instructionsBright = false;
  String? _cameraError;
  late Future<PetStreakSummary> _streakFuture;
  late final CaptureViewModel _viewModel;
  late final AnimationController _recordingProgressController;

  @override
  void initState() {
    super.initState();
    _viewModel = CaptureViewModel();
    _recordingProgressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _instructionsBright = true);
    });
    _instructionPulseTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted && !_recording) setState(() => _instructionsBright = false);
    });
    _instructionReturnTimer = Timer(const Duration(milliseconds: 4400), () {
      if (mounted && !_recording) setState(() => _instructionsBright = true);
    });
    _streakFuture = _loadStreak();
    _initialiseCamera();
    if (widget.openGalleryOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickImage());
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _instructionPulseTimer?.cancel();
    _instructionReturnTimer?.cancel();
    _recordingProgressController.dispose();
    _viewModel.dispose();
    _cameraController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<VideoPlayerController> _createFallbackPreviewController() async {
    final controller = VideoPlayerController.asset(_fallbackPreviewAsset);
    await controller.initialize();
    await controller.setLooping(true);
    await controller.play();
    return controller;
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
        // imageFormatGroup: Platform.isAndroid
        //     ? ImageFormatGroup.nv21
        //     : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      final minZoom = await controller.getMinZoomLevel();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      final maxZoom = await controller.getMaxZoomLevel();
      final usableMaxZoom = maxZoom < _maxUserZoom ? maxZoom : _maxUserZoom;
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _zoomRequestCoordinator = null;
        _zoom = CameraZoomState(
          min: minZoom,
          max: usableMaxZoom,
          current: clampZoom(1, minZoom, usableMaxZoom),
        );
        _cameraLoading = false;
        _cameraError = null;
      });
      await _applyZoom(_zoom.current);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraLoading = false;
        _cameraError = _cameraMessage(error);
      });
    }
  }

  Future<void> _startRecording() async {
    if (_analyzingVideo) return;

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      _setDemoPreview();
      return;
    }

    if (_recording) return;

    try {
      await controller.startVideoRecording();
      _viewModel.hideZoomMultipliers();
      setState(() {
        _recording = true;
      });
      _recordingProgressController.forward(from: 0);
      _recordingTimer?.cancel();
      _recordingTimer = Timer(const Duration(seconds: 10), _stopRecording);
      if (!_recordGestureActive) await _stopRecording();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = _cameraMessage(error));
    }
  }

  Future<void> _stopRecording() async {
    final controller = _cameraController;
    if (!_recording || controller == null) return;

    _recordingTimer?.cancel();
    _recordingProgressController.stop();

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
        await _analyzeVideo(File(file.path), sourceLabel: 'Captured video');
      } finally {
        if (mounted) {
          setState(() {
            _analyzingVideo = false;
          });
        }
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = _cameraMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _recording = false;
        });
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_recording || _analyzingImage || _analyzingVideo) return;
    final mediaType = await showModalBottomSheet<_GalleryMediaType>(
      context: context,
      backgroundColor: const Color(0xFF1A1F24),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_outlined,
                  color: PetTheme.ivory,
                ),
                title: const Text(
                  'Upload photo',
                  style: TextStyle(color: PetTheme.ivory),
                ),
                onTap: () => Navigator.of(context).pop(_GalleryMediaType.image),
              ),
              ListTile(
                leading: const Icon(
                  Icons.videocam_outlined,
                  color: PetTheme.ivory,
                ),
                title: const Text(
                  'Upload video',
                  style: TextStyle(color: PetTheme.ivory),
                ),
                onTap: () => Navigator.of(context).pop(_GalleryMediaType.video),
              ),
            ],
          ),
        );
      },
    );
    if (mediaType == null) return;

    if (mediaType == _GalleryMediaType.image) {
      await _pickImage();
      return;
    }
    await _pickVideo();
  }

  Future<void> _pickImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image == null) return;

      await _analyzeImage(File(image.path), sourceLabel: 'Uploaded image');
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = _cameraMessage(error));
    }
  }

  Future<void> _pickVideo() async {
    try {
      final video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 10),
      );
      if (video == null) return;

      await _analyzeVideo(File(video.path), sourceLabel: 'Uploaded video');
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = _cameraMessage(error));
    }
  }

  Future<void> _takePhoto() async {
    if (_recording || _analyzingImage || _analyzingVideo) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      _setDemoPreview();
      return;
    }
    try {
      final image = await controller.takePicture();
      await _analyzeImage(File(image.path), sourceLabel: 'Captured photo');
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = _cameraMessage(error));
    }
  }

  Future<void> _analyzeImage(File image, {required String sourceLabel}) async {
    try {
      if (mounted) {
        setState(() {
          _analyzingImage = true;
          _cameraError = null;
        });
      }

      // Run the on-device/ML perception model and the agentic backend's
      // visual-search upload concurrently — they're independent and the
      // upload is best-effort, so it must never block or fail the ML
      // emotion result.
      final visualSearchUpload = _uploadForVisualSearch(image);

      try {
        final prediction = await widget.visualLlmClient.predictImageEmotion(
          image,
        );
        final uploadedImagePath = await visualSearchUpload;
        await _setPreview(
          PetCaptureResult(
            kind: CaptureMediaKind.image,
            species: 'cat',
            emotion: prediction.predictedEmotion,
            emotionConfidence: prediction.confidence,
            emotionProbabilities: prediction.detailBreakdown,
            healthFlags: const [],
            sourceLabel: sourceLabel,
            path: image.path,
            uploadedImagePath: uploadedImagePath,
            petId: widget.petId,
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
        final uploadedImagePath = await visualSearchUpload;
        await _setPreview(
          PetCaptureResult(
            kind: CaptureMediaKind.image,
            species: 'cat',
            emotion: 'watchful',
            healthFlags: const ['needs review'],
            sourceLabel: sourceLabel,
            path: image.path,
            uploadedImagePath: uploadedImagePath,
            petId: widget.petId,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _analyzingImage = false);
    }
  }

  Future<void> _analyzeVideo(File video, {required String sourceLabel}) async {
    try {
      if (mounted) {
        setState(() {
          _analyzingVideo = true;
          _cameraError = null;
        });
      }
      final prediction = await widget.visualLlmClient.predictVideoEmotion(
        video,
      );
      await _setPreview(
        PetCaptureResult(
          kind: CaptureMediaKind.video,
          species: 'cat',
          emotion: prediction.predictedEmotion,
          emotionConfidence: prediction.confidence,
          emotionProbabilities: prediction.detailBreakdown,
          healthFlags: const [],
          sourceLabel: sourceLabel,
          path: video.path,
          petId: widget.petId,
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
          sourceLabel: sourceLabel,
          path: video.path,
          petId: widget.petId,
        ),
      );
    } finally {
      if (mounted) setState(() => _analyzingVideo = false);
    }
  }

  /// Uploads [image] to the agentic backend so an "attached_image_path"
  /// can ride along in the perception payload's notes, letting the
  /// orchestrator trigger a subagent's `visual_search` tool (breed/
  /// condition identification via Google Lens). This is a second, separate
  /// pipeline from `widget.visualLlmClient` above — failures here are
  /// swallowed (returns null) so a flaky/offline backend never blocks the
  /// on-device emotion result from reaching the preview.
  Future<String?> _uploadForVisualSearch(File image) async {
    try {
      final uploaded = await widget.client.uploadMedia(image);
      return uploaded.path.isEmpty ? null : uploaded.path;
    } on Object catch (error) {
      debugPrint('Visual search upload skipped: $error');
      return null;
    }
  }

  Future<void> _setPreview(PetCaptureResult result) async {
    await _videoController?.dispose();
    VideoPlayerController? controller;
    try {
      if (result.kind == CaptureMediaKind.video && result.path != null) {
        controller = VideoPlayerController.file(File(result.path!));
        await controller.initialize();
        await controller.setLooping(true);
        await controller.play();
      } else if (result.kind == CaptureMediaKind.demo) {
        controller = await _createFallbackPreviewController();
      }
    } on Object {
      await controller?.dispose();
      controller = null;
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
    _viewModel.showReplay();
  }

  Future<PetStreakSummary> _loadStreak() {
    return widget.streakClient.fetchStreakSummary(petId: widget.petId);
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
        PetCaptureResult(
          kind: CaptureMediaKind.demo,
          species: 'cat',
          emotion: 'distress',
          healthFlags: ['limping', 'low appetite'],
          sourceLabel: 'Demo capture',
          petId: widget.petId,
        ),
      ),
    );
  }

  void _retake() {
    _videoController?.dispose();
    setState(() {
      _preview = null;
      _videoController = null;
      _zoom = _zoom.copyWith(current: 1);
      _momentSaved = false;
      _savingMoment = false;
    });
    _viewModel.showCapture();
    unawaited(_applyZoom(1));
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
      String? uploadedImagePath = preview.uploadedImagePath;
      if (uploadedImagePath == null && preview.path != null) {
        uploadedImagePath = await _uploadForVisualSearch(File(preview.path!));
      }
      final updatedPreview = preview.copyWith(uploadedImagePath: uploadedImagePath);
      await _recordPetMoment(updatedPreview);
      if (!mounted) return;
      setState(() => _momentSaved = true);
      await _playTransition(CaptureTransitionTarget.save);
      if (!mounted) return;
      _retake();
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

  Future<void> _askAgent() async {
    final preview = _preview;
    if (preview == null) return;
    await _playTransition(CaptureTransitionTarget.agent);
    if (!mounted) return;
    await Navigator.of(context).push(
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

  Future<void> _playTransition(CaptureTransitionTarget target) async {
    _viewModel.beginTransition(target);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _viewModel.endTransition();
  }

  Future<void> _beginRecordGesture(LongPressStartDetails details) async {
    _recordGestureActive = true;
    _viewModel.hideZoomMultipliers();
    _shutterZoomStartY = details.globalPosition.dy;
    _shutterZoomAtStart = _zoom.current;
    await _startRecording();
  }

  void _moveRecordGesture(LongPressMoveUpdateDetails details) {
    if (!_recordGestureActive) return;
    unawaited(
      _applyZoom(
        zoomForVerticalDrag(
          baseZoom: _shutterZoomAtStart,
          startY: _shutterZoomStartY,
          currentY: details.globalPosition.dy,
          minZoom: _zoom.min,
          maxZoom: _zoom.max,
        ),
      ),
    );
  }

  void _endRecordGesture() {
    _recordGestureActive = false;
    if (_recording) unawaited(_stopRecording());
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

  Future<void> _applyZoom(double value) async {
    final controller = _cameraController;
    final nextZoom = clampZoom(value, _zoom.min, _zoom.max);
    if ((nextZoom - _zoom.current).abs() < 0.05) {
      return;
    }
    if (!mounted) return;
    setState(() => _zoom = _zoom.copyWith(current: nextZoom));
    if (controller == null || !controller.value.isInitialized) return;
    _zoomRequestCoordinator ??= CameraZoomRequestCoordinator((target) async {
      try {
        await controller.setZoomLevel(target);
      } on Object {
        // Some simulator/device cameras report zoom ranges they cannot apply.
      }
    });
    await _zoomRequestCoordinator!.request(nextZoom);
  }

  void _onPreviewScaleStart(ScaleStartDetails details) {
    _zoomAtScaleStart = _zoom.current;
  }

  void _onPreviewScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) return;
    _viewModel.revealZoomMultipliers();
    final zoom = zoomForScale(
      baseZoom: _zoomAtScaleStart,
      scale: details.scale,
      minZoom: _zoom.min,
      maxZoom: _zoom.max,
    );
    unawaited(_applyZoom(zoom));
  }

  void _revealZoomFromDivider(DragEndDetails details) {
    if (_recording || details.primaryVelocity == null) return;
    if (details.primaryVelocity! < -80) {
      _viewModel.revealZoomMultipliers();
    }
  }

  void _selectZoomPreset(double zoom) {
    if (_recording || zoom < _zoom.min || zoom > _zoom.max) return;
    _viewModel.revealZoomMultipliers();
    unawaited(_applyZoom(zoom));
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
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final preview = _preview;
        final uiState = _viewModel.state;
        final isReplay =
            uiState.mode == CaptureScreenMode.replay && preview != null;
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (!isReplay)
                _CameraBackdrop(
                  controller: _cameraController,
                  loading: _cameraLoading,
                  error: _cameraError,
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
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
                  child: Column(
                    children: [
                      _CaptureTopBar(
                        streakFuture: _streakFuture,
                        onOpenStreak: _openStreakCalendar,
                        onOpenPetRoom: _openPetRoom,
                        onDemo: preview?.kind == CaptureMediaKind.demo
                            ? null
                            : _setDemoPreview,
                      ),
                      Expanded(
                        child: !isReplay
                            ? _CaptureModeUi(
                                recording: _recording,
                                analyzing: _analyzingImage || _analyzingVideo,
                                instructionsBright: _instructionsBright,
                                scanningLabel: 'TAP PHOTO · HOLD VIDEO',
                                showZoomMultipliers:
                                    uiState.showZoomMultipliers,
                                zoom: _zoom,
                                recordingProgress: _recordingProgressController,
                                onDividerSwipeEnd: _revealZoomFromDivider,
                                onZoomPreset: _selectZoomPreset,
                                onGallery: _pickFromGallery,
                                onShutterTap: _takePhoto,
                                onRecordStart: (details) =>
                                    unawaited(_beginRecordGesture(details)),
                                onRecordMove: _moveRecordGesture,
                                onRecordEnd: _endRecordGesture,
                                onChat: _openChatWithoutCapture,
                              )
                            : _ReplayModeUi(
                                result: preview,
                                saving: _savingMoment,
                                onRetake: _retake,
                                onSave: _saveMoment,
                                onAskAgent: () => unawaited(_askAgent()),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_recording)
                AnimatedBuilder(
                  animation: _recordingProgressController,
                  builder: (context, _) => IgnorePointer(
                    child: CustomPaint(
                      painter: _RecordingFramePainter(
                        progress: _recordingProgressController.value,
                      ),
                    ),
                  ),
                ),
              if (uiState.transitionTarget != null)
                _GamificationTransition(target: uiState.transitionTarget!),
            ],
          ),
        );
      },
    );
  }

  void _openChatWithoutCapture() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AgentChatScreen(
          client: widget.client,
          streakClient: widget.streakClient,
          visualLlmClient: widget.visualLlmClient,
          textToSpeechService: widget.textToSpeechService,
          autoReadPreferenceStore: widget.autoReadPreferenceStore,
        ),
      ),
    );
  }

  void _openStreakCalendar() {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (context) => PetMomentStreakScreen(
              streakClient: widget.streakClient,
              petId: widget.petId,
              petName: widget.petName,
            ),
          ),
        )
        .then((_) => _refreshStreak());
  }

  void _openPetRoom() {
    Navigator.of(context).maybePop();
  }
}

class _CameraBackdrop extends StatelessWidget {
  const _CameraBackdrop({
    required this.controller,
    required this.loading,
    required this.error,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onTapPreview,
  });

  final CameraController? controller;
  final bool loading;
  final String? error;
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
                CameraPreviewCover(
                  sensorAspectRatio: camera.value.aspectRatio,
                  preview: CameraPreview(camera),
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

class _PreviewBackdrop extends StatefulWidget {
  const _PreviewBackdrop({required this.result, required this.videoController});

  final PetCaptureResult result;
  final VideoPlayerController? videoController;

  @override
  State<_PreviewBackdrop> createState() => _PreviewBackdropState();
}

class _PreviewBackdropState extends State<_PreviewBackdrop> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void didUpdateWidget(covariant _PreviewBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result.path != widget.result.path ||
        oldWidget.result.kind != widget.result.kind) {
      _visible = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  Widget _buildVideoBackdrop(VideoPlayerController controller) {
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.videoController;
    if ((widget.result.kind == CaptureMediaKind.video ||
            widget.result.kind == CaptureMediaKind.demo) &&
        controller != null &&
        controller.value.isInitialized) {
      return AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        child: _buildVideoBackdrop(controller),
      );
    }

    if (widget.result.kind == CaptureMediaKind.image &&
        widget.result.path != null) {
      return Image.file(File(widget.result.path!), fit: BoxFit.cover);
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
    required this.onOpenPetRoom,
    required this.onDemo,
  });

  final Future<PetStreakSummary> streakFuture;
  final VoidCallback onOpenStreak;
  final VoidCallback onOpenPetRoom;
  final VoidCallback? onDemo;

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
          tooltip: 'Pet room',
          onPressed: onOpenPetRoom,
          icon: const Icon(Icons.home_rounded, color: PetTheme.ivory),
        ),
        Opacity(
          opacity: onDemo == null ? 0.38 : 1,
          child: IconButton(
            tooltip: 'Demo capture',
            onPressed: onDemo,
            icon: const Icon(Icons.preview, color: PetTheme.ivory),
          ),
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

class _CaptureModeUi extends StatelessWidget {
  const _CaptureModeUi({
    required this.recording,
    required this.analyzing,
    required this.instructionsBright,
    required this.scanningLabel,
    required this.showZoomMultipliers,
    required this.zoom,
    required this.recordingProgress,
    required this.onDividerSwipeEnd,
    required this.onZoomPreset,
    required this.onGallery,
    required this.onShutterTap,
    required this.onRecordStart,
    required this.onRecordMove,
    required this.onRecordEnd,
    required this.onChat,
  });

  final bool recording;
  final bool analyzing;
  final bool instructionsBright;
  final String scanningLabel;
  final bool showZoomMultipliers;
  final CameraZoomState zoom;
  final Animation<double> recordingProgress;
  final GestureDragEndCallback onDividerSwipeEnd;
  final ValueChanged<double> onZoomPreset;
  final VoidCallback onGallery;
  final VoidCallback onShutterTap;
  final ValueChanged<LongPressStartDetails> onRecordStart;
  final ValueChanged<LongPressMoveUpdateDetails> onRecordMove;
  final VoidCallback onRecordEnd;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 620;
        return Column(
          children: [
            const Spacer(),
            AnimatedOpacity(
              key: const Key('capture-instructions'),
              opacity: recording ? 0 : (instructionsBright ? 1 : 0),
              duration: Duration(milliseconds: recording ? 180 : 1600),
              curve: Curves.easeInOut,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  children: [
                    Text(
                      'Capture The Meowment',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: PetTheme.ivory,
                        fontSize: compact ? 24 : 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Record up to 10 seconds or upload a picture for the health agent.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: PetTheme.ivory,
                        fontSize: 14,
                        height: 1.35,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: compact ? 6 : 10),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: showZoomMultipliers && !recording
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ZoomMultipliers(
                        zoom: zoom,
                        onSelected: onZoomPreset,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            GestureDetector(
              key: const Key('capture-status-divider'),
              behavior: HitTestBehavior.opaque,
              onVerticalDragEnd: recording ? null : onDividerSwipeEnd,
              child: const SizedBox(
                width: 112,
                height: 24,
                child: Center(
                  child: SizedBox(
                    width: 80,
                    child: Divider(
                      height: 2,
                      thickness: 4,
                      color: Color(0xB3FFFFFF),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: compact ? 4 : 8),
            AnimatedBuilder(
              animation: recordingProgress,
              builder: (context, _) {
                final remaining = (10 * (1 - recordingProgress.value)).ceil();
                return _LivePetIndicator(
                  label: recording ? '$remaining SEC' : scanningLabel,
                  recording: recording,
                );
              },
            ),
            SizedBox(height: compact ? 10 : 16),
            _StoryCaptureControls(
              recording: recording,
              analyzing: analyzing,
              onGallery: onGallery,
              onShutterTap: onShutterTap,
              onRecordStart: onRecordStart,
              onRecordMove: onRecordMove,
              onRecordEnd: onRecordEnd,
              onChat: onChat,
            ),
          ],
        );
      },
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

class _ZoomMultipliers extends StatelessWidget {
  const _ZoomMultipliers({required this.zoom, required this.onSelected});

  final CameraZoomState zoom;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    const levels = [0.5, 1.0, 2.0, 5.0];
    final active = levels.reduce(
      (left, right) =>
          (zoom.current - left).abs() <= (zoom.current - right).abs()
          ? left
          : right,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final level in levels)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Builder(
              builder: (context) {
                final enabled = level >= zoom.min && level <= zoom.max;
                return Tooltip(
                  message: enabled
                      ? 'Set ${level == 0.5 ? '.5' : level.toInt()}x zoom'
                      : 'Not supported by this camera',
                  child: InkResponse(
                    key: Key('zoom-preset-$level'),
                    onTap: enabled ? () => onSelected(level) : null,
                    radius: 24,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: active == level ? 44 : 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active == level
                            ? PetTheme.ivory
                            : const Color(0x66000000),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        level == 0.5 ? '.5x' : '${level.toInt()}x',
                        style: TextStyle(
                          color: !enabled
                              ? PetTheme.muted.withValues(alpha: 0.55)
                              : active == level
                              ? Colors.black
                              : PetTheme.ivory,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _StoryCaptureControls extends StatelessWidget {
  const _StoryCaptureControls({
    required this.recording,
    required this.analyzing,
    required this.onGallery,
    required this.onShutterTap,
    required this.onRecordStart,
    required this.onRecordMove,
    required this.onRecordEnd,
    required this.onChat,
  });

  final bool recording;
  final bool analyzing;
  final VoidCallback onGallery;
  final VoidCallback onShutterTap;
  final ValueChanged<LongPressStartDetails> onRecordStart;
  final ValueChanged<LongPressMoveUpdateDetails> onRecordMove;
  final VoidCallback onRecordEnd;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _RoundIconButton(
          tooltip: analyzing ? 'Analyzing pet moment' : 'Upload from gallery',
          icon: analyzing ? Icons.hourglass_top : Icons.add,
          onPressed: analyzing || recording ? null : onGallery,
        ),
        Semantics(
          button: true,
          label: 'Tap for photo. Hold for video.',
          child: GestureDetector(
            key: const Key('story-shutter'),
            onTap: analyzing || recording ? null : onShutterTap,
            onLongPressStart: analyzing ? null : onRecordStart,
            onLongPressMoveUpdate: analyzing ? null : onRecordMove,
            onLongPressEnd: analyzing ? null : (_) => onRecordEnd(),
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
                    color: analyzing
                        ? PetTheme.warning
                        : recording
                        ? PetTheme.coral
                        : PetTheme.ivory,
                    borderRadius: BorderRadius.circular(recording ? 8 : 40),
                  ),
                  child: analyzing
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

class _LivePetIndicator extends StatefulWidget {
  const _LivePetIndicator({required this.label, required this.recording});

  final String label;
  final bool recording;

  @override
  State<_LivePetIndicator> createState() => _LivePetIndicatorState();
}

class _LivePetIndicatorState extends State<_LivePetIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
      lowerBound: 0.45,
      upperBound: 1,
    )..repeat(reverse: true, count: 3);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x55FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: _pulse,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.recording
                      ? PetTheme.coral
                      : const Color(0xFF47E46A),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                          (widget.recording
                                  ? PetTheme.coral
                                  : const Color(0xFF47E46A))
                              .withValues(alpha: 0.65),
                      blurRadius: 9,
                    ),
                  ],
                ),
                child: const SizedBox.square(dimension: 8),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: const TextStyle(
                color: PetTheme.ivory,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplayModeUi extends StatelessWidget {
  const _ReplayModeUi({
    required this.result,
    required this.saving,
    required this.onRetake,
    required this.onSave,
    required this.onAskAgent,
  });

  final PetCaptureResult result;
  final bool saving;
  final VoidCallback onRetake;
  final VoidCallback onSave;
  final VoidCallback onAskAgent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            const SizedBox(height: 18),
            Wrap(
              key: const Key('preview-ml-tags'),
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusPill(label: result.species.toUpperCase()),
                _StatusPill(label: result.emotion.toUpperCase()),
                if (result.emotionConfidence != null)
                  _StatusPill(
                    label:
                        '${(result.emotionConfidence! * 100).round()}% CONFIDENCE',
                  ),
              ],
            ),
            const Spacer(),
            _PreviewActions(
              saving: saving,
              onRetake: onRetake,
              onSave: onSave,
              onAskAgent: onAskAgent,
            ),
          ],
        );
      },
    );
  }
}

class _PreviewActions extends StatelessWidget {
  const _PreviewActions({
    required this.saving,
    required this.onRetake,
    required this.onSave,
    required this.onAskAgent,
  });

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
                onPressed: saving ? null : onSave,
                icon: saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save Moment'),
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
        ),
      ],
    );
  }
}

class _RecordingFramePainter extends CustomPainter {
  const _RecordingFramePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(7, 7, size.width - 14, size.height - 14),
      const Radius.circular(22),
    );
    final path = Path()..addRRect(frame);
    final metric = path.computeMetrics().first;
    final visible = metric.extractPath(0, metric.length * progress.clamp(0, 1));
    final glow = Paint()
      ..color = PetTheme.coral.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final line = Paint()
      ..color = PetTheme.coral
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawPath(visible, glow)
      ..drawPath(visible, line);
  }

  @override
  bool shouldRepaint(covariant _RecordingFramePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _GamificationTransition extends StatefulWidget {
  const _GamificationTransition({required this.target});

  final CaptureTransitionTarget target;

  @override
  State<_GamificationTransition> createState() =>
      _GamificationTransitionState();
}

class _GamificationTransitionState extends State<_GamificationTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.18), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 1), weight: 45),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saving = widget.target == CaptureTransitionTarget.save;
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xD9000000),
        child: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _controller,
              curve: const Interval(0, 0.65, curve: Curves.easeOut),
            ),
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.local_fire_department,
                    color: PetTheme.coral,
                    size: 92,
                    shadows: [Shadow(color: PetTheme.warning, blurRadius: 22)],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    saving ? 'Moment Saved' : 'Moment Ready',
                    style: const TextStyle(
                      color: PetTheme.ivory,
                      fontSize: 24,
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

enum _GalleryMediaType { image, video }
