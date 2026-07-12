import 'package:amd_pet_frontend/ui/features/home/models/pet_room_state.dart';
import 'package:amd_pet_frontend/ui/features/home/view_models/isometric_home_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

const primaryPetId = 'mochi';
const secondaryPetId = 'luna';

PetRoomPetState petState(IsometricHomeViewModel viewModel, String petId) {
  return viewModel.state.pets.firstWhere((pet) => pet.id == petId);
}

PetRoomPetState _makePet(String id, String name) {
  return PetRoomPetState(
    id: id,
    stats: PetStats(name: name, species: 'Cat', emotion: 'Sleepy'),
    activeAction: standbyActionById(PetStandbyActionId.sleepAndWake),
    normalizedPosition: const Offset(0.54, 0.72),
  );
}

IsometricHomeViewModel _viewModelWithPets({
  StandbyActionSelector? actionSelector,
}) {
  return IsometricHomeViewModel(
    actionSelector: actionSelector,
    initialPets: [
      _makePet(primaryPetId, 'Mochi'),
      _makePet(secondaryPetId, 'Luna'),
    ],
  );
}

void main() {
  group('roomAssetsFor', () {
    final cases = <(DateTime, IsometricRoomAssets)>[
      (DateTime(2026, 7, 11, 5, 59), nightRoomAssets),
      (DateTime(2026, 7, 11, 6), earlyMorningRoomAssets),
      (DateTime(2026, 7, 11, 10, 59), earlyMorningRoomAssets),
      (DateTime(2026, 7, 11, 11), brightNoonRoomAssets),
      (DateTime(2026, 7, 11, 16, 59), brightNoonRoomAssets),
      (DateTime(2026, 7, 11, 17), sunsetRoomAssets),
      (DateTime(2026, 7, 11, 19, 59), sunsetRoomAssets),
      (DateTime(2026, 7, 11, 20), nightRoomAssets),
    ];

    for (final testCase in cases) {
      test('maps ${testCase.$1} to its room asset', () {
        expect(roomAssetsFor(testCase.$1), same(testCase.$2));
      });
    }

    test('currentRoomAssets uses the injected device clock', () {
      expect(
        currentRoomAssets(clock: () => DateTime(2026, 7, 11, 17)),
        same(sunsetRoomAssets),
      );
    });

    test('each period resolves a background and transparent room pair', () {
      expect(
        earlyMorningRoomAssets.backgroundAssetPath,
        contains('/background/'),
      );
      expect(
        earlyMorningRoomAssets.transparentRoomAssetPath,
        contains('/transparent/'),
      );
    });
  });

  group('standby actions', () {
    test('registers every supplied GIF', () {
      expect(petStandbyActions, hasLength(8));
      expect(
        petStandbyActions.map((action) => action.assetPath),
        containsAll(const [
          'assets/images/cat-animations/sprite-animation-1-walking-front.gif',
          'assets/images/cat-animations/sprite-animation-2-walking-right.gif',
          'assets/images/cat-animations/sprite-animation-3-walking-back.gif',
          'assets/images/cat-animations/sprite-animation-4-walking-left.gif',
          'assets/images/cat-animations/'
              'sprite-animation-5-walking-front-and-sit.gif',
          'assets/images/cat-animations/'
              'sprite-animation-6-sit-and-lick-hand.gif',
          'assets/images/cat-animations/'
              'sprite-animation-7-walking-right-and-lay.gif',
          'assets/images/cat-animations/'
              'sprite-animation-8-sleep.gif',
        ]),
      );
    });

    test('directional GIFs translate along their matching axis', () {
      expect(
        standbyActionById(PetStandbyActionId.walkingFront).movement,
        const Offset(0, 0.08),
      );
      expect(
        standbyActionById(PetStandbyActionId.walkingBack).movement,
        const Offset(0, -0.08),
      );
      expect(
        standbyActionById(PetStandbyActionId.walkingRight).movement,
        const Offset(0.10, 0),
      );
      expect(
        standbyActionById(PetStandbyActionId.walkingLeft).movement,
        const Offset(-0.10, 0),
      );
    });

    test('positions are clamped to the room floor', () {
      expect(
        clampPetPosition(const Offset(-1, 2)),
        const Offset(petFloorMinX, petFloorMaxY),
      );
      expect(
        clampPetPosition(const Offset(2, -1)),
        const Offset(petFloorMaxX, petFloorMinY),
      );
    });

    test('walk and sit forces a sitting follow-up', () {
      final viewModel = _viewModelWithPets(
        actionSelector: (candidates) => candidates.firstWhere(
          (action) => action.id == PetStandbyActionId.walkingFrontAndSit,
        ),
      );
      addTearDown(viewModel.dispose);

      viewModel.advanceStandby();
      expect(
        petState(viewModel, primaryPetId).activeAction.id,
        PetStandbyActionId.walkingFrontAndSit,
      );

      viewModel.advanceStandby();
      expect(
        petState(viewModel, primaryPetId).activeAction.id,
        PetStandbyActionId.sitAndLick,
      );
    });

    test('walk and lay forces a sleeping follow-up', () {
      final viewModel = _viewModelWithPets(
        actionSelector: (candidates) => candidates.firstWhere(
          (action) => action.id == PetStandbyActionId.walkingRightAndLay,
        ),
      );
      addTearDown(viewModel.dispose);

      viewModel.advanceStandby();
      expect(
        petState(viewModel, primaryPetId).activeAction.id,
        PetStandbyActionId.walkingRightAndLay,
      );

      viewModel.advanceStandby();
      expect(
        petState(viewModel, primaryPetId).activeAction.id,
        PetStandbyActionId.sleepAndWake,
      );
    });

    test('secondary pet advances without changing the primary pet', () {
      final viewModel = _viewModelWithPets(
        actionSelector: (candidates) => candidates.firstWhere(
          (action) => action.id == PetStandbyActionId.walkingLeft,
        ),
      );
      addTearDown(viewModel.dispose);
      final primaryBefore = petState(viewModel, primaryPetId);

      viewModel.advancePetStandby(secondaryPetId);

      expect(petState(viewModel, primaryPetId), same(primaryBefore));
      expect(
        petState(viewModel, secondaryPetId).activeAction.id,
        PetStandbyActionId.walkingLeft,
      );
    });

    test('pet selection toggles without stopping standby', () {
      final viewModel = _viewModelWithPets();
      addTearDown(viewModel.dispose);
      viewModel.startStandby();

      viewModel.togglePetStats(primaryPetId);

      expect(viewModel.state.isStatCardVisible, isTrue);
      expect(viewModel.state.selectedPet?.stats.name, 'Mochi');
      expect(viewModel.isStandbyRunning, isTrue);

      viewModel.togglePetStats(secondaryPetId);
      expect(viewModel.state.selectedPet?.stats.name, 'Luna');

      viewModel.togglePetStats(secondaryPetId);
      expect(viewModel.state.isStatCardVisible, isFalse);
    });
  });
}
