import 'package:amd_pet_frontend/ui/features/capture/view_models/capture_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capture view model owns mode and replay tracking state', () {
    final viewModel = CaptureViewModel();
    addTearDown(viewModel.dispose);

    expect(viewModel.state.mode, CaptureScreenMode.capture);
    expect(viewModel.state.trackingMode, isFalse);

    viewModel.showReplay();
    viewModel.toggleTrackingMode();

    expect(viewModel.state.mode, CaptureScreenMode.replay);
    expect(viewModel.state.trackingMode, isTrue);

    viewModel.showCapture();

    expect(viewModel.state.mode, CaptureScreenMode.capture);
    expect(viewModel.state.trackingMode, isFalse);
  });

  test('capture transition target is explicit and clearable', () {
    final viewModel = CaptureViewModel();
    addTearDown(viewModel.dispose);

    viewModel.beginTransition(CaptureTransitionTarget.agent);
    expect(viewModel.state.transitionTarget, CaptureTransitionTarget.agent);

    viewModel.endTransition();
    expect(viewModel.state.transitionTarget, isNull);
  });
}
