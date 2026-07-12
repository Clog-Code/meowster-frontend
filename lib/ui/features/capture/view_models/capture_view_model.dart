import 'dart:async';

import 'package:flutter/foundation.dart';

enum CaptureScreenMode { capture, replay }

enum CaptureTransitionTarget { save, agent }

@immutable
class CaptureUiState {
  const CaptureUiState({
    required this.mode,
    required this.showZoomMultipliers,
    this.transitionTarget,
  });

  const CaptureUiState.initial()
    : mode = CaptureScreenMode.capture,
      showZoomMultipliers = false,
      transitionTarget = null;

  final CaptureScreenMode mode;
  final bool showZoomMultipliers;
  final CaptureTransitionTarget? transitionTarget;

  CaptureUiState copyWith({
    CaptureScreenMode? mode,
    bool? showZoomMultipliers,
    CaptureTransitionTarget? transitionTarget,
    bool clearTransition = false,
  }) {
    return CaptureUiState(
      mode: mode ?? this.mode,
      showZoomMultipliers: showZoomMultipliers ?? this.showZoomMultipliers,
      transitionTarget: clearTransition
          ? null
          : transitionTarget ?? this.transitionTarget,
    );
  }
}

class CaptureViewModel extends ChangeNotifier {
  CaptureUiState _state = const CaptureUiState.initial();
  Timer? _zoomVisibilityTimer;

  CaptureUiState get state => _state;

  void showReplay() => _setState(
    _state.copyWith(mode: CaptureScreenMode.replay, showZoomMultipliers: false),
  );

  void showCapture() => _setState(
    _state.copyWith(
      mode: CaptureScreenMode.capture,
      showZoomMultipliers: false,
      clearTransition: true,
    ),
  );

  void revealZoomMultipliers() {
    _zoomVisibilityTimer?.cancel();
    if (!_state.showZoomMultipliers) {
      _setState(_state.copyWith(showZoomMultipliers: true));
    }
    _zoomVisibilityTimer = Timer(const Duration(seconds: 4), () {
      _setState(_state.copyWith(showZoomMultipliers: false));
    });
  }

  void hideZoomMultipliers() {
    _zoomVisibilityTimer?.cancel();
    if (_state.showZoomMultipliers) {
      _setState(_state.copyWith(showZoomMultipliers: false));
    }
  }

  void beginTransition(CaptureTransitionTarget target) {
    _setState(_state.copyWith(transitionTarget: target));
  }

  void endTransition() {
    _setState(_state.copyWith(clearTransition: true));
  }

  void _setState(CaptureUiState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _zoomVisibilityTimer?.cancel();
    super.dispose();
  }
}
