enum CaptureMediaKind { video, image, demo }

class PetCaptureResult {
  const PetCaptureResult({
    required this.kind,
    required this.species,
    required this.emotion,
    required this.healthFlags,
    required this.sourceLabel,
    this.petId = 'pet-01',
    this.emotionConfidence,
    this.emotionProbabilities,
    this.path,
    this.uploadedImagePath,
  });

  PetCaptureResult copyWith({
    CaptureMediaKind? kind,
    String? species,
    String? emotion,
    List<String>? healthFlags,
    String? sourceLabel,
    String? petId,
    double? emotionConfidence,
    Map<String, double>? emotionProbabilities,
    List<PetTrackingSample>? trackingSamples,
    String? path,
    String? uploadedImagePath,
  }) {
    return PetCaptureResult(
      kind: kind ?? this.kind,
      species: species ?? this.species,
      emotion: emotion ?? this.emotion,
      healthFlags: healthFlags ?? this.healthFlags,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      petId: petId ?? this.petId,
      emotionConfidence: emotionConfidence ?? this.emotionConfidence,
      emotionProbabilities: emotionProbabilities ?? this.emotionProbabilities,
      trackingSamples: trackingSamples ?? this.trackingSamples,
      path: path ?? this.path,
      uploadedImagePath: uploadedImagePath ?? this.uploadedImagePath,
    );
  }

  final CaptureMediaKind kind;
  final String species;
  final String emotion;
  final List<String> healthFlags;
  final String sourceLabel;
  final String petId;
  final double? emotionConfidence;
  final Map<String, double>? emotionProbabilities;
  final String? path;

  /// Server-side absolute path returned by the agentic backend's
  /// `POST /upload`, when this capture was also uploaded there. Threaded
  /// into the perception payload's `notes` so the orchestrator can pass it
  /// on to a subagent's `visual_search` tool (breed/condition ID via Google
  /// Lens) — independent of the on-device ML emotion model above.
  final String? uploadedImagePath;

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
      'pet_id': petId,
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
      'pet_id': petId,
      'pet_profile': mockPetProfile,
      'species': species,
      'emotion': emotion,
      'emotion_confidence': emotionConfidence ?? 0.82,
      if (emotionProbabilities != null)
        'emotion_probabilities': emotionProbabilities,
      'health_flags': healthFlags,
      'thread_id': threadId,
      'timestamp': DateTime.now().toIso8601String(),
      'image_path': uploadedImagePath,
      'notes': [
        emotionConfidence == null
            ? 'Frontend MVP simulated perception from ${kind.name} capture.'
            : 'Frontend MVP visual LLM perception from ${kind.name} capture.',
        // Picked up by the orchestrator's delegation rules (see
        // initializer_prompt.md: "pass an image URL or path when one is
        // available") to trigger the visual_search tool in a subagent.
        if (uploadedImagePath != null)
          'attached_image_path: $uploadedImagePath',
      ].join(' '),
    };
  }
}
