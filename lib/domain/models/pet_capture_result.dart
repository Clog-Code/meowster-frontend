enum CaptureMediaKind { video, image, demo }

class PetCaptureResult {
  const PetCaptureResult({
    required this.kind,
    required this.species,
    required this.emotion,
    required this.healthFlags,
    required this.sourceLabel,
    this.path,
  });

  final CaptureMediaKind kind;
  final String species;
  final String emotion;
  final List<String> healthFlags;
  final String sourceLabel;
  final String? path;

  String get attachmentLabel {
    final labels = [species, emotion, ...healthFlags].join(' / ');
    return '$sourceLabel: $labels';
  }

  Map<String, dynamic> toPerceptionPayload(String threadId) {
    return {
      'pet_id': 'pet-01',
      'species': species,
      'emotion': emotion,
      'emotion_confidence': 0.82,
      'health_flags': healthFlags,
      'thread_id': threadId,
      'timestamp': DateTime.now().toIso8601String(),
      'notes': 'Frontend MVP simulated perception from ${kind.name} capture.',
    };
  }
}
