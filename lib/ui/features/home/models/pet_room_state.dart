import 'dart:ui';

import 'package:flutter/foundation.dart';

enum PetStandbyActionId {
  walkingFront,
  walkingRight,
  walkingBack,
  walkingLeft,
  walkingFrontAndSit,
  sitAndLick,
  walkingRightAndLay,
  sleepAndWake,
}

@immutable
class IsometricRoomAssets {
  const IsometricRoomAssets({
    required this.backgroundAssetPath,
    required this.transparentRoomAssetPath,
  });

  final String backgroundAssetPath;
  final String transparentRoomAssetPath;
}

@immutable
class PetStats {
  const PetStats({
    required this.name,
    required this.species,
    required this.emotion,
    this.breed,
    this.weightKg,
    this.lifeStage,
    this.knownConditions,
    this.deliveryAddress,
    this.preferredClinic,
    this.preferredFoodBrand,
  });

  final String name;
  final String species;
  final String emotion;
  final String? breed;
  final double? weightKg;
  final String? lifeStage;
  final String? knownConditions;
  final String? deliveryAddress;
  final String? preferredClinic;
  final String? preferredFoodBrand;

  PetStats copyWith({
    String? name,
    String? species,
    String? emotion,
    String? breed,
    double? weightKg,
    String? lifeStage,
    String? knownConditions,
    String? deliveryAddress,
    String? preferredClinic,
    String? preferredFoodBrand,
  }) {
    return PetStats(
      name: name ?? this.name,
      species: species ?? this.species,
      emotion: emotion ?? this.emotion,
      breed: breed ?? this.breed,
      weightKg: weightKg ?? this.weightKg,
      lifeStage: lifeStage ?? this.lifeStage,
      knownConditions: knownConditions ?? this.knownConditions,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      preferredClinic: preferredClinic ?? this.preferredClinic,
      preferredFoodBrand: preferredFoodBrand ?? this.preferredFoodBrand,
    );
  }
}

@immutable
class PetStandbyAction {
  const PetStandbyAction({
    required this.id,
    required this.assetPath,
    required this.duration,
    required this.movement,
    required this.weight,
    this.followUp,
  });

  final PetStandbyActionId id;
  final String assetPath;
  final Duration duration;
  final Offset movement;
  final int weight;
  final PetStandbyActionId? followUp;
}

@immutable
class PetRoomPetState {
  const PetRoomPetState({
    required this.id,
    required this.stats,
    required this.activeAction,
    required this.normalizedPosition,
  });

  final String id;
  final PetStats stats;
  final PetStandbyAction activeAction;
  final Offset normalizedPosition;

  PetRoomPetState copyWith({
    PetStats? stats,
    PetStandbyAction? activeAction,
    Offset? normalizedPosition,
  }) {
    return PetRoomPetState(
      id: id,
      stats: stats ?? this.stats,
      activeAction: activeAction ?? this.activeAction,
      normalizedPosition: normalizedPosition ?? this.normalizedPosition,
    );
  }
}

@immutable
class PetRoomState {
  const PetRoomState({
    required this.roomAssets,
    required this.pets,
    this.selectedPetId,
    this.isWelcomeMode = false, 
  });

  final IsometricRoomAssets roomAssets;
  final List<PetRoomPetState> pets;
  final String? selectedPetId;
  final bool isWelcomeMode;

  bool get isStatCardVisible => selectedPetId != null;

  PetRoomPetState? get selectedPet {
    final id = selectedPetId;
    if (id == null) return null;
    for (final pet in pets) {
      if (pet.id == id) return pet;
    }
    return null;
  }

  PetRoomState copyWith({
    IsometricRoomAssets? roomAssets,
    List<PetRoomPetState>? pets,
    String? selectedPetId,
    bool clearSelectedPet = false,
    bool? isWelcomeMode,
  }) {
    return PetRoomState(
      roomAssets: roomAssets ?? this.roomAssets,
      pets: pets ?? this.pets,
      selectedPetId: clearSelectedPet
          ? null
          : selectedPetId ?? this.selectedPetId,
      isWelcomeMode: isWelcomeMode ?? this.isWelcomeMode,
    );
  }
}
