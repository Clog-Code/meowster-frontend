class PetStreakDay {
  const PetStreakDay({
    required this.date,
    required this.captureCount,
    this.dominantEmotion,
    this.species,
    this.imagePath,
  });

  factory PetStreakDay.fromJson(Map<String, dynamic> json) {
    return PetStreakDay(
      date: DateTime.parse(json['date'].toString()),
      captureCount: _readInt(json['capture_count'] ?? json['captureCount']),
      dominantEmotion: json['dominant_emotion']?.toString(),
      species: json['species']?.toString(),
      imagePath: json['image_path']?.toString() ?? json['imagePath']?.toString(),
    );
  }

  final DateTime date;
  final int captureCount;
  final String? dominantEmotion;
  final String? species;
  final String? imagePath;

  bool get hasCapture => captureCount > 0;

  bool get isHealthy {
    final emotion = dominantEmotion?.trim().toLowerCase();
    return emotion != null &&
        const {
          'normal',
          'curious',
          'rested',
          'playful',
          'happy',
          'calm',
          'surprised',
        }.contains(emotion);
  }
}

class PetStreakSummary {
  const PetStreakSummary({
    required this.currentStreak,
    required this.longestStreak,
    required this.monthStart,
    required this.days,
  });

  factory PetStreakSummary.empty({DateTime? monthStart}) {
    final now = DateTime.now();
    return PetStreakSummary(
      currentStreak: 0,
      longestStreak: 0,
      monthStart: monthStart ?? DateTime(now.year, now.month),
      days: const [],
    );
  }

  factory PetStreakSummary.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];
    return PetStreakSummary(
      currentStreak: _readInt(json['current_streak'] ?? json['currentStreak']),
      longestStreak: _readInt(json['longest_streak'] ?? json['longestStreak']),
      monthStart: DateTime.parse(json['month_start'].toString()),
      days: rawDays is List
          ? rawDays
                .whereType<Map>()
                .map(
                  (day) =>
                      PetStreakDay.fromJson(Map<String, dynamic>.from(day)),
                )
                .toList()
          : const [],
    );
  }

  final int currentStreak;
  final int longestStreak;
  final DateTime monthStart;
  final List<PetStreakDay> days;

  int get momentsThisMonth =>
      days.fold(0, (total, day) => total + day.captureCount);

  int capturedDaysInMonth(DateTime month) {
    return daysForMonth(month).where((day) => day.hasCapture).length;
  }

  int momentsInMonth(DateTime month) {
    return daysForMonth(
      month,
    ).fold(0, (total, day) => total + day.captureCount);
  }

  List<PetStreakDay> daysForMonth(DateTime month) {
    return days
        .where(
          (day) => day.date.year == month.year && day.date.month == month.month,
        )
        .toList();
  }

  PetStreakDay? dayFor(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    for (final day in days) {
      final dayDate = DateTime(day.date.year, day.date.month, day.date.day);
      if (dayDate == normalized) return day;
    }
    return null;
  }
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
