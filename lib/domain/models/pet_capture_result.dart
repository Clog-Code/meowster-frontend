enum CaptureMediaKind { video, image, demo }

class PetCaptureResult {
  const PetCaptureResult({
    required this.kind,
    required this.species,
    required this.emotion,
    required this.healthFlags,
    required this.sourceLabel,
    this.emotionConfidence,
    this.emotionProbabilities,
    this.path,
  });

  final CaptureMediaKind kind;
  final String species;
  final String emotion;
  final List<String> healthFlags;
  final String sourceLabel;
  final double? emotionConfidence;
  final Map<String, double>? emotionProbabilities;
  final String? path;

  String get attachmentLabel {
    final labels = [species, emotion, ...healthFlags].join(' / ');
    return '$sourceLabel: $labels';
  }

  String get userDescription {
    final flags = healthFlags.isEmpty
        ? 'no visible flags'
        : healthFlags.join(', ');
    return '$species appears $emotion; observed $flags.';
  }

  Map<String, dynamic> get mockPetProfile {
    return {
      'pet_id': 'pet-01',
      'name': 'Mochi',
      'species': species,
      'breed': species == 'cat' ? 'Domestic Shorthair' : null,
      'weight_kg': species == 'cat' ? 4.2 : null,
      'life_stage': 'adult',
      'known_conditions': healthFlags.contains('limping')
          ? 'Occasional limping'
          : '',
      'delivery_address': '',
      'preferred_clinic': '',
      'preferred_food_brand': '',
    };
  }

  Map<String, dynamic> toPerceptionPayload(String threadId) {
    return {
      'pet_id': 'pet-01',
      'pet_profile': mockPetProfile,
      'species': species,
      'emotion': emotion,
      'emotion_confidence': emotionConfidence ?? 0.82,
      if (emotionProbabilities != null)
        'emotion_probabilities': emotionProbabilities,
      'health_flags': healthFlags,
      'thread_id': threadId,
      'timestamp': DateTime.now().toIso8601String(),
      'notes': emotionConfidence == null
          ? 'Frontend MVP simulated perception from ${kind.name} capture.'
          : 'Frontend MVP visual LLM perception from ${kind.name} capture.',
    };
  }
}
