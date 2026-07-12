import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A single locally-saved pet moment capture (photo or video).
class LocalMomentRecord {
  const LocalMomentRecord({
    required this.date,
    required this.filePath,
    required this.isVideo,
  });

  final DateTime date;
  final String filePath;
  final bool isVideo;

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'filePath': filePath,
        'isVideo': isVideo,
      };

  factory LocalMomentRecord.fromJson(Map<String, dynamic> json) {
    return LocalMomentRecord(
      date: DateTime.parse(json['date'] as String),
      filePath: json['filePath'] as String,
      isVideo: json['isVideo'] as bool? ?? false,
    );
  }
}

/// Saves captured pet moment media (photos/videos) into a persistent local
/// folder on the device (app documents directory) and keeps a small JSON
/// index so the streak page can look up "what did I capture on this day"
/// without needing the backend.
///
/// Camera/gallery plugins usually hand back a path into a temp/cache
/// directory, which the OS can wipe at any time. This copies the file into
/// a stable location so it survives app restarts.
class LocalMomentStorage {
  LocalMomentStorage._();
  static final LocalMomentStorage instance = LocalMomentStorage._();

  static const _indexFileName = 'pet_moments_index.json';
  static const _mediaFolderName = 'pet_moments';

  Future<Directory> _mediaDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${docsDir.path}/$_mediaFolderName');
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir;
  }

  Future<File> _indexFile() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return File('${docsDir.path}/$_indexFileName');
  }

  Future<List<LocalMomentRecord>> _readIndex() async {
    final file = await _indexFile();
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (item) => LocalMomentRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    } on Object {
      // Corrupt or unreadable index; treat as empty rather than crash.
      return [];
    }
  }

  Future<void> _writeIndex(List<LocalMomentRecord> records) async {
    final file = await _indexFile();
    final encoded = jsonEncode(records.map((r) => r.toJson()).toList());
    await file.writeAsString(encoded);
  }

  /// Copies [sourcePath] into the app's persistent documents folder and
  /// records it against [capturedAt] (defaults to now). Returns the new
  /// persistent path.
  Future<String> saveMoment({
    required String sourcePath,
    required bool isVideo,
    DateTime? capturedAt,
  }) async {
    final date = capturedAt ?? DateTime.now();
    final mediaDir = await _mediaDirectory();
    final extension = sourcePath.contains('.')
        ? sourcePath.substring(sourcePath.lastIndexOf('.'))
        : (isVideo ? '.mp4' : '.jpg');
    final fileName = 'moment_${date.millisecondsSinceEpoch}$extension';
    final destinationPath = '${mediaDir.path}/$fileName';

    await File(sourcePath).copy(destinationPath);

    final records = await _readIndex();
    records.add(
      LocalMomentRecord(date: date, filePath: destinationPath, isVideo: isVideo),
    );
    await _writeIndex(records);

    return destinationPath;
  }

  /// Returns the most recent local moment captured on [date] (matching
  /// year/month/day only), or null if nothing was captured that day.
  Future<LocalMomentRecord?> momentForDate(DateTime date) async {
    final matches = await momentsForDate(date);
    if (matches.isEmpty) return null;
    return matches.first;
  }

  /// Returns ALL local moments captured on [date] (matching year/month/day
  /// only), most recent first. Use this when a day may have multiple snaps.
  Future<List<LocalMomentRecord>> momentsForDate(DateTime date) async {
    final records = await _readIndex();
    final matches = records
        .where(
          (record) =>
              record.date.year == date.year &&
              record.date.month == date.month &&
              record.date.day == date.day,
        )
        .toList();
    matches.sort((a, b) => b.date.compareTo(a.date));
    return matches;
  }

  /// Returns all locally saved moments, most recent first.
  Future<List<LocalMomentRecord>> allMoments() async {
    final records = await _readIndex();
    records.sort((a, b) => b.date.compareTo(a.date));
    return records;
  }
}