import 'package:amd_pet_frontend/data/services/pet_streak_client.dart';
import 'package:amd_pet_frontend/ui/features/home/models/pet_room_state.dart';
import 'package:amd_pet_frontend/ui/features/home/view_models/isometric_home_view_model.dart';
import 'package:amd_pet_frontend/ui/features/home/views/isometric_home_page.dart';
import 'package:amd_pet_frontend/ui/features/streak/pet_moment_streak_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildTestApp(IsometricHomeViewModel viewModel) {
  return MaterialApp(
    home: IsometricHomePage(
      viewModel: viewModel,
      streakClient: const EmptyPetStreakClient(),
      captureScreenBuilder: (context) =>
          const Scaffold(body: Center(child: Text('Camera destination'))),
      chatScreenBuilder: (context, _) =>
          const Scaffold(body: Center(child: Text('Chat destination'))),
    ),
  );
}

PetRoomPetState _makePet(String id, String name, {String emotion = 'Sleepy'}) {
  return PetRoomPetState(
    id: id,
    stats: PetStats(name: name, species: 'Cat', emotion: emotion),
    activeAction: standbyActionById(PetStandbyActionId.sleepAndWake),
    normalizedPosition: const Offset(0.54, 0.72),
  );
}

void main() {
  testWidgets('renders paired room layers and two pets', (tester) async {
    final viewModel = IsometricHomeViewModel(
      clock: () => DateTime(2026, 7, 11, 12),
      initialPets: [
        _makePet('mochi', 'Mochi'),
        _makePet('luna', 'Luna'),
      ],
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(_buildTestApp(viewModel));
    await tester.pump();

    final background = tester.widget<Image>(
      find.byKey(const Key('isometric-room-background')),
    );
    expect(background.image, isA<AssetImage>());
    expect(
      (background.image as AssetImage).assetName,
      brightNoonRoomAssets.backgroundAssetPath,
    );
    final transparentRoom = tester.widget<Image>(
      find.byKey(const Key('isometric-transparent-room')),
    );
    expect(
      (transparentRoom.image as AssetImage).assetName,
      brightNoonRoomAssets.transparentRoomAssetPath,
    );
    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const Key('isometric-room-viewer')),
    );
    expect(viewer.minScale, 0.8);
    expect(viewer.maxScale, 3);
    expect(find.byKey(const Key('pet-mochi-sprite')), findsOneWidget);
    expect(find.byKey(const Key('pet-luna-sprite')), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey(
          'assets/images/cat-animations/'
          'sprite-animation-8-sleep.gif',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('pet tap toggles the glass stat card', (tester) async {
    final viewModel = IsometricHomeViewModel(
      initialPets: [
        _makePet('mochi', 'Mochi'),
        _makePet('luna', 'Luna'),
      ],
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(_buildTestApp(viewModel));
    await tester.pump();

    expect(find.byKey(const Key('pet-stat-card')), findsNothing);

    await tester.tap(find.byKey(const Key('pet-mochi-sprite')));
    await tester.pump();

    expect(find.byKey(const Key('pet-stat-card')), findsOneWidget);
    expect(find.text('Mochi'), findsOneWidget);
    expect(find.text('Cat'), findsOneWidget);
    expect(find.text('Sleepy'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pet-mochi-sprite')));
    await tester.pump();

    expect(find.byKey(const Key('pet-stat-card')), findsNothing);
  });

  testWidgets('each pet opens its own stats', (tester) async {
    final viewModel = IsometricHomeViewModel(
      initialPets: [
        _makePet('mochi', 'Mochi'),
        _makePet('luna', 'Luna', emotion: 'Curious'),
      ],
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(_buildTestApp(viewModel));

    await tester.tap(find.byKey(const Key('pet-mochi-sprite')));
    await tester.pump();
    expect(find.text('Mochi'), findsOneWidget);
    expect(find.text('Sleepy'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pet-luna-sprite')));
    await tester.pump();
    expect(find.text('Luna'), findsOneWidget);
    expect(find.text('Curious'), findsOneWidget);
    expect(find.text('Mochi'), findsNothing);
  });

  testWidgets('fixed overlays navigate to streaks and camera', (tester) async {
    final viewModel = IsometricHomeViewModel(
      initialPets: [
        _makePet('mochi', 'Mochi'),
        _makePet('luna', 'Luna'),
      ],
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(_buildTestApp(viewModel));

    await tester.tap(find.byTooltip('Open pet moment streak calendar'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(PetMomentStreakScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(PetMomentStreakScreen))).pop();
    await tester.pump();

    await tester.tap(find.byKey(const Key('pet-mochi-sprite')));
    await tester.pump();
    await tester.tap(find.byTooltip('Open camera'));
    await tester.pumpAndSettle();
    expect(find.text('Camera destination'), findsOneWidget);
  });

  testWidgets('expanded layout remains overflow-free', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = IsometricHomeViewModel();
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(_buildTestApp(viewModel));
    await tester.tap(find.byKey(const Key('pet-mochi-sprite')));
    await tester.pump();

    expect(find.byKey(const Key('pet-stat-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
