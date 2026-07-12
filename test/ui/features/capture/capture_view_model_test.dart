import 'package:amd_pet_frontend/ui/features/capture/view_models/capture_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capture view model owns capture and replay mode', () {
    final viewModel = CaptureViewModel();
    addTearDown(viewModel.dispose);

    expect(viewModel.state.mode, CaptureScreenMode.capture);

    viewModel.showReplay();

    expect(viewModel.state.mode, CaptureScreenMode.replay);

    viewModel.showCapture();

    expect(viewModel.state.mode, CaptureScreenMode.capture);
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
