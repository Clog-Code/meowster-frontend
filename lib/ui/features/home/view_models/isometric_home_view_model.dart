import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../../data/services/agent_stream_client.dart';
import '../../../../data/services/pet_streak_client.dart';
import '../models/pet_room_state.dart';

typedef DeviceClock = DateTime Function();
typedef StandbyActionSelector =
    PetStandbyAction Function(List<PetStandbyAction> candidates);

const IsometricRoomAssets earlyMorningRoomAssets = IsometricRoomAssets(
  backgroundAssetPath:
      'assets/images/isometric-cozy-bedroom/background/'
      'isometric-cozy-bedroom-1-early-morning-background.png',
  transparentRoomAssetPath:
      'assets/images/isometric-cozy-bedroom/transparent/'
      'isometric-cozy-bedroom-1-early-morning-transparent.png',
);
const IsometricRoomAssets brightNoonRoomAssets = IsometricRoomAssets(
  backgroundAssetPath:
      'assets/images/isometric-cozy-bedroom/background/'
      'isometric-cozy-bedroom-2-bright-noon-daylight-background.png',
  transparentRoomAssetPath:
      'assets/images/isometric-cozy-bedroom/transparent/'
      'isometric-cozy-bedroom-2-bright-noon-daylight-transparent.png',
);
const IsometricRoomAssets sunsetRoomAssets = IsometricRoomAssets(
  backgroundAssetPath:
      'assets/images/isometric-cozy-bedroom/background/'
      'isometric-cozy-bedroom-3-golden-hour-sunset-background.png',
  transparentRoomAssetPath:
      'assets/images/isometric-cozy-bedroom/transparent/'
      'isometric-cozy-bedroom-3-golden-hour-sunset-transparent.png',
);
const IsometricRoomAssets nightRoomAssets = IsometricRoomAssets(
  backgroundAssetPath:
      'assets/images/isometric-cozy-bedroom/background/'
      'isometric-cozy-bedroom-4-late-at-night-background.png',
  transparentRoomAssetPath:
      'assets/images/isometric-cozy-bedroom/transparent/'
      'isometric-cozy-bedroom-4-late-at-night-transparent.png',
);

const String _catAnimationDirectory = 'assets/images/cat-animations';

const List<PetStandbyAction> petStandbyActions = [
  PetStandbyAction(
    id: PetStandbyActionId.walkingFront,
    assetPath: '$_catAnimationDirectory/sprite-animation-1-walking-front.gif',
    duration: Duration(seconds: 4),
    movement: Offset(0, 0.08),
    weight: 2,
  ),
  PetStandbyAction(
    id: PetStandbyActionId.walkingRight,
    assetPath: '$_catAnimationDirectory/sprite-animation-2-walking-right.gif',
    duration: Duration(seconds: 4),
    movement: Offset(0.10, 0),
    weight: 2,
  ),
  PetStandbyAction(
    id: PetStandbyActionId.walkingBack,
    assetPath: '$_catAnimationDirectory/sprite-animation-3-walking-back.gif',
    duration: Duration(seconds: 4),
    movement: Offset(0, -0.08),
    weight: 2,
  ),
  PetStandbyAction(
    id: PetStandbyActionId.walkingLeft,
    assetPath: '$_catAnimationDirectory/sprite-animation-4-walking-left.gif',
    duration: Duration(seconds: 4),
    movement: Offset(-0.10, 0),
    weight: 2,
  ),
  PetStandbyAction(
    id: PetStandbyActionId.walkingFrontAndSit,
    assetPath:
        '$_catAnimationDirectory/sprite-animation-5-walking-front-and-sit.gif',
    duration: Duration(seconds: 5),
    movement: Offset(0, 0.07),
    weight: 2,
    followUp: PetStandbyActionId.sitAndLick,
  ),
  PetStandbyAction(
    id: PetStandbyActionId.sitAndLick,
    assetPath:
        '$_catAnimationDirectory/sprite-animation-6-sit-and-lick-hand.gif',
    duration: Duration(seconds: 8),
    movement: Offset.zero,
    weight: 5,
  ),
  PetStandbyAction(
    id: PetStandbyActionId.walkingRightAndLay,
    assetPath:
        '$_catAnimationDirectory/sprite-animation-7-walking-right-and-lay.gif',
    duration: Duration(seconds: 5),
    movement: Offset(0.09, 0),
    weight: 2,
    followUp: PetStandbyActionId.sleepAndWake,
  ),
  PetStandbyAction(
    id: PetStandbyActionId.sleepAndWake,
    assetPath: '$_catAnimationDirectory/sprite-animation-8-sleep.gif',
    duration: Duration(seconds: 10),
    movement: Offset.zero,
    weight: 6,
  ),
];

const double petFloorMinX = 0.32;
const double petFloorMaxX = 0.74;
const double petFloorMinY = 0.59;
const double petFloorMaxY = 0.82;
final List<Offset> _petPositions = const [
  Offset(0.50, 0.74),
  Offset(0.66, 0.66),
  Offset(0.38, 0.64),
  Offset(0.58, 0.58),
];

IsometricRoomAssets roomAssetsFor(DateTime localTime) {
  final hour = localTime.hour;
  if (hour >= 6 && hour < 11) return earlyMorningRoomAssets;
  if (hour >= 11 && hour < 17) return brightNoonRoomAssets;
  if (hour >= 17 && hour < 20) return sunsetRoomAssets;
  return nightRoomAssets;
}

IsometricRoomAssets currentRoomAssets({DeviceClock clock = DateTime.now}) {
  return roomAssetsFor(clock());
}

PetStandbyAction standbyActionById(PetStandbyActionId id) {
  return petStandbyActions.firstWhere((action) => action.id == id);
}

Offset clampPetPosition(Offset position) {
  return Offset(
    position.dx.clamp(petFloorMinX, petFloorMaxX),
    position.dy.clamp(petFloorMinY, petFloorMaxY),
  );
}

class IsometricHomeViewModel extends ChangeNotifier {
  IsometricHomeViewModel({
    DeviceClock clock = DateTime.now,
    Random? random,
    this.actionSelector,
    this.client,
    this.streakClient,
  }) : _clock = clock,
       _random = random ?? Random(),
       _state = PetRoomState(
         roomAssets: currentRoomAssets(clock: clock),
         pets: const [],
       );

  final DeviceClock _clock;
  final Random _random;
  final StandbyActionSelector? actionSelector;
  final AgentStreamClient? client;
  final PetStreakClient? streakClient;
  int? currentStreak;
  final Map<String, Timer> _standbyTimers = {};
  final Map<String, PetStandbyActionId> _forcedNextActions = {};
  bool _isStandbyRunning = false;
  bool _petsLoaded = false;
  PetRoomState _state;

  Future<void> loadPets() async {
    final c = client;
    if (c == null) return;
    try {
      final petList = await c.fetchPetProfiles();
      if (petList.isEmpty) return;

      final petStates = <PetRoomPetState>[];
      for (var i = 0; i < petList.length; i++) {
        final p = petList[i];
        final petId = p['pet_id']?.toString() ?? '';
        if (petId.isEmpty) continue;
        final position = i < _petPositions.length
            ? _petPositions[i]
            : Offset(0.54, 0.72);
        petStates.add(PetRoomPetState(
          id: petId,
          stats: PetStats(
            name: p['name']?.toString() ?? 'Pet ${i + 1}',
            species: p['species']?.toString() ?? '',
            emotion: 'Sleepy',
          ),
          activeAction: standbyActionById(PetStandbyActionId.sleepAndWake),
          normalizedPosition: position,
        ));
      }

      if (petStates.isEmpty) return;
      _state = _state.copyWith(pets: List.unmodifiable(petStates));
      _petsLoaded = true;
      notifyListeners();

      for (final pet in petStates) {
        loadPetProfile(pet.id);
      }
      _loadStreak();
    } on AgentConnectionException {
      // Backend unavailable.
    }
  }

  void refreshStreak() {
    _loadStreak();
  }

  Future<void> _loadStreak() async {
    final c = streakClient;
    if (c == null) return;
    final petId = _state.selectedPetId ?? _state.pets.firstOrNull?.id;
    if (petId == null) return;
    try {
      final summary = await c.fetchStreakSummary(petId: petId);
      currentStreak = summary.currentStreak;
      notifyListeners();
    } on AgentConnectionException {
      // Streak backend unavailable.
    }
  }

  Future<void> loadPetProfile(String petId) async {
    final c = client;
    if (c == null) return;
    try {
      final profile = await c.fetchPetProfile(petId);
      if (profile == null) return;
      final petIndex = _state.pets.indexWhere((pet) => pet.id == petId);
      if (petIndex == -1) return;

      final pet = _state.pets[petIndex];
      final stats = pet.stats.copyWith(
        name: profile['name']?.toString() ?? pet.stats.name,
        species: profile['species']?.toString() ?? pet.stats.species,
        breed: profile['breed']?.toString(),
        weightKg: profile['weight_kg'] != null
            ? (profile['weight_kg'] as num).toDouble()
            : null,
        lifeStage: profile['life_stage']?.toString(),
        knownConditions: profile['known_conditions']?.toString(),
        deliveryAddress: profile['delivery_address']?.toString(),
        preferredClinic: profile['preferred_clinic']?.toString(),
        preferredFoodBrand: profile['preferred_food_brand']?.toString(),
      );
      final pets = List<PetRoomPetState>.of(_state.pets);
      pets[petIndex] = pet.copyWith(stats: stats);
      _state = _state.copyWith(pets: List.unmodifiable(pets));
      notifyListeners();
    } on AgentConnectionException {
      // Backend unavailable.
    }
  }

  PetRoomState get state => _state;
  bool get isStandbyRunning => _isStandbyRunning;

  void clearSelection() {
    _state = _state.copyWith(clearSelectedPet: true);
    currentStreak = null;
    notifyListeners();
  }

  void togglePetStats(String petId) {
    if (!_state.pets.any((pet) => pet.id == petId)) return;
    final isAlreadySelected = _state.selectedPetId == petId;
    _state = _state.copyWith(
      selectedPetId: isAlreadySelected ? null : petId,
      clearSelectedPet: isAlreadySelected,
    );
    notifyListeners();
    if (!isAlreadySelected) _loadStreak();
  }

  void refreshBackground() {
    final roomAssets = currentRoomAssets(clock: _clock);
    if (identical(roomAssets, _state.roomAssets)) return;
    _state = _state.copyWith(roomAssets: roomAssets);
    notifyListeners();
  }

  bool _isWelcomeMode = false;
  bool get isWelcomeMode => _isWelcomeMode;

  void triggerWelcome() {
    _isWelcomeMode = true;
    notifyListeners();
    
    Future.delayed(const Duration(seconds: 4), () {
      _isWelcomeMode = false;
      notifyListeners();
    });
  }

  void startStandby() {
    if (_isStandbyRunning) return;
    _isStandbyRunning = true;
    if (!_petsLoaded) {
      loadPets().then((_) {
        for (final pet in _state.pets) {
          _scheduleNextAction(pet.id);
        }
        triggerWelcome();
      });
    } else {
      for (final pet in _state.pets) {
        _scheduleNextAction(pet.id);
      }
      triggerWelcome();
    }
  }

  void pauseStandby() {
    _isStandbyRunning = false;
    for (final timer in _standbyTimers.values) {
      timer.cancel();
    }
    _standbyTimers.clear();
  }

  void resumeStandby() {
    refreshBackground();
    _isStandbyRunning = false;
    _petsLoaded = false;
    _standbyTimers.clear();
    _forcedNextActions.clear();
    startStandby();
  }

  void advanceStandby() {
    if (_state.pets.isNotEmpty) {
      advancePetStandby(_state.pets.first.id);
    }
  }

  void advancePetStandby(String petId) {
    final petIndex = _state.pets.indexWhere((pet) => pet.id == petId);
    if (petIndex == -1) return;

    final pet = _state.pets[petIndex];
    final forcedAction = _forcedNextActions.remove(petId);
    final nextAction = forcedAction == null
        ? _selectAction(_eligibleActions(pet))
        : standbyActionById(forcedAction);
    final followUp = nextAction.followUp;
    if (followUp != null) _forcedNextActions[petId] = followUp;

    final nextPet = pet.copyWith(
      activeAction: nextAction,
      normalizedPosition: _nextPosition(pet, nextAction),
    );
    final pets = List<PetRoomPetState>.of(_state.pets);
    pets[petIndex] = nextPet;
    _state = _state.copyWith(pets: List.unmodifiable(pets));
    notifyListeners();
    if (_isStandbyRunning) _scheduleNextAction(petId);
  }

  Offset _nextPosition(PetRoomPetState pet, PetStandbyAction action) {
    final candidate = clampPetPosition(
      pet.normalizedPosition + action.movement,
    );
    for (final otherPet in _state.pets) {
      if (otherPet.id == pet.id) continue;
      if ((candidate - otherPet.normalizedPosition).distance < 0.11) {
        return pet.normalizedPosition;
      }
    }
    return candidate;
  }

  List<PetStandbyAction> _eligibleActions(PetRoomPetState pet) {
    return petStandbyActions
        .where((action) {
          if (action.movement == Offset.zero) return true;
          return clampPetPosition(pet.normalizedPosition + action.movement) !=
              pet.normalizedPosition;
        })
        .toList(growable: false);
  }

  PetStandbyAction _selectAction(List<PetStandbyAction> candidates) {
    final selector = actionSelector;
    if (selector != null) return selector(candidates);

    final totalWeight = candidates.fold<int>(
      0,
      (total, action) => total + action.weight,
    );
    var roll = _random.nextInt(totalWeight);
    for (final action in candidates) {
      roll -= action.weight;
      if (roll < 0) return action;
    }
    return candidates.last;
  }

  void _scheduleNextAction(String petId) {
    _standbyTimers.remove(petId)?.cancel();
    final pet = _state.pets.firstWhere((item) => item.id == petId);
    _standbyTimers[petId] = Timer(
      pet.activeAction.duration,
      () => advancePetStandby(petId),
    );
  }

  @override
  void dispose() {
    pauseStandby();
    super.dispose();
  }
}
