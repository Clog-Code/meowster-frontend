import 'dart:convert';
import 'dart:io';

import '../../domain/models/pet_streak_summary.dart';
import 'agent_stream_client.dart';

abstract class PetStreakClient {
  Future<PetStreakSummary> fetchStreakSummary({String petId = 'pet-01'});
}

class EmptyPetStreakClient implements PetStreakClient {
  const EmptyPetStreakClient();

  @override
  Future<PetStreakSummary> fetchStreakSummary({String petId = 'pet-01'}) async {
    return PetStreakSummary.empty();
  }
}

class DemoPetStreakClient implements PetStreakClient {
  const DemoPetStreakClient();

  @override
  Future<PetStreakSummary> fetchStreakSummary({String petId = 'pet-01'}) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    PetStreakDay day(
      int offset,
      int captureCount,
      String emotion, {
      String species = 'cat',
    }) {
      return PetStreakDay(
        date: now.add(Duration(days: offset)),
        captureCount: captureCount,
        dominantEmotion: emotion,
        species: species,
      );
    }

    return PetStreakSummary(
      currentStreak: 8,
      longestStreak: 16,
      monthStart: monthStart,
      days: [
        day(-44, 1, 'curious'),
        day(-42, 2, 'happy'),
        day(-39, 1, 'sad'),
        day(-36, 1, 'calm'),
        day(-34, 3, 'playful'),
        day(-31, 1, 'normal'),
        day(-27, 1, 'surprised'),
        day(-25, 2, 'curious'),
        day(-22, 1, 'distress'),
        day(-18, 1, 'rested'),
        day(-14, 2, 'happy'),
        day(-10, 1, 'calm'),
        day(-9, 2, 'curious'),
        day(-8, 1, 'rested'),
        day(-7, 1, 'distress'),
        day(-6, 2, 'playful'),
        day(-5, 1, 'happy'),
        day(-4, 1, 'watchful'),
        day(-3, 2, 'surprised'),
        day(-2, 1, 'normal'),
        day(-1, 1, 'curious'),
        day(0, 2, 'playful'),
      ],
    );
  }
}

class AgentPetStreakClient implements PetStreakClient {
  const AgentPetStreakClient({required this.baseUri});

  factory AgentPetStreakClient.fromEnvironment() {
    const configured = String.fromEnvironment(
      'AGENT_BASE_URL',
      defaultValue: 'http://localhost:8000',
    );
    return AgentPetStreakClient(baseUri: Uri.parse(configured));
  }

  final Uri baseUri;

  @override
  Future<PetStreakSummary> fetchStreakSummary({String petId = 'pet-01'}) async {
    final uri = baseUri
        .resolve('/pet-moments/streaks')
        .replace(queryParameters: {'pet_id': petId});
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = body.trim().isEmpty ? '' : ': ${body.trim()}';
        throw AgentConnectionException(
          'Backend request failed (${response.statusCode}) at $uri$detail',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Streak response must be a JSON object.');
      }
      return PetStreakSummary.fromJson(decoded);
    } on AgentConnectionException {
      rethrow;
    } on SocketException catch (error) {
      throw AgentConnectionException('Could not connect to $uri: $error');
    } finally {
      client.close();
    }
  }
}
