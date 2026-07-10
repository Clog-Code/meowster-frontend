import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class VisualLlmPrediction {
  const VisualLlmPrediction({
    required this.predictedEmotion,
    required this.confidence,
    required this.detailBreakdown,
    required this.isVideo,
  });

  final String predictedEmotion;
  final double confidence;
  final Map<String, double> detailBreakdown;
  final bool isVideo;

  Map<String, double> get allProbabilities => detailBreakdown;

  factory VisualLlmPrediction.fromJson(Map<String, dynamic> json) {
    final rawEmotion = json['predicted_emotion'];
    final rawConfidence = json['confidence'];
    final rawBreakdown = json['detail_breakdown'] ?? json['all_probabilities'];
    final rawIsVideo = json['is_video'];

    if (rawEmotion is! String || rawEmotion.trim().isEmpty) {
      throw const FormatException('Missing predicted_emotion');
    }
    if (rawConfidence is! num) {
      throw const FormatException('Missing confidence');
    }
    if (rawBreakdown is! Map<String, dynamic>) {
      throw const FormatException('Missing detail_breakdown');
    }

    return VisualLlmPrediction(
      predictedEmotion: rawEmotion.trim(),
      confidence: rawConfidence.toDouble(),
      isVideo: rawIsVideo == true,
      detailBreakdown: rawBreakdown.map((key, value) {
        if (value is! num) {
          throw FormatException('Breakdown value for $key is not numeric');
        }
        return MapEntry(key, value.toDouble());
      }),
    );
  }
}

abstract class VisualLlmClient {
  Future<VisualLlmPrediction> predictImageEmotion(File imageFile);

  Future<VisualLlmPrediction> predictVideoEmotion(File videoFile);
}

class VisualLlmApiClient implements VisualLlmClient {
  VisualLlmApiClient({required this.baseUri, http.Client? client})
    : _client = client ?? http.Client();

  factory VisualLlmApiClient.fromEnvironment() {
    const configured = String.fromEnvironment(
      'VISUAL_MODEL_BASE_URL',
      defaultValue: 'http://localhost:8001',
    );
    return VisualLlmApiClient(baseUri: Uri.parse(configured));
  }

  final Uri baseUri;
  final http.Client _client;

  @override
  Future<VisualLlmPrediction> predictImageEmotion(File imageFile) {
    return _predict(
      endpoint: '/predict',
      file: imageFile,
      contentType: _contentTypeFor(
        imageFile,
        fallback: http.MediaType('image', 'jpeg'),
      ),
    );
  }

  @override
  Future<VisualLlmPrediction> predictVideoEmotion(File videoFile) {
    return _predict(
      endpoint: '/predict_video',
      file: videoFile,
      contentType: _contentTypeFor(
        videoFile,
        fallback: http.MediaType('video', 'mp4'),
      ),
    );
  }

  Future<VisualLlmPrediction> _predict({
    required String endpoint,
    required File file,
    required http.MediaType contentType,
  }) async {
    final uri = baseUri.resolve(endpoint);
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          contentType: contentType,
        ),
      );

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = response.body.trim().isEmpty
          ? ''
          : ': ${response.body.trim()}';
      throw VisualLlmException(
        'Visual LLM request failed (${response.statusCode}) at $uri$detail',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Visual LLM response must be a JSON object');
    }
    return VisualLlmPrediction.fromJson(decoded);
  }

  http.MediaType _contentTypeFor(
    File file, {
    required http.MediaType fallback,
  }) {
    final extension = file.path.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => http.MediaType('image', 'jpeg'),
      'png' => http.MediaType('image', 'png'),
      'heic' => http.MediaType('image', 'heic'),
      'webp' => http.MediaType('image', 'webp'),
      'mp4' => http.MediaType('video', 'mp4'),
      'mov' => http.MediaType('video', 'quicktime'),
      'm4v' => http.MediaType('video', 'x-m4v'),
      'avi' => http.MediaType('video', 'x-msvideo'),
      _ => fallback,
    };
  }
}

class DisabledVisualLlmClient implements VisualLlmClient {
  const DisabledVisualLlmClient();

  @override
  Future<VisualLlmPrediction> predictImageEmotion(File imageFile) {
    throw const VisualLlmException('Visual LLM client is not configured.');
  }

  @override
  Future<VisualLlmPrediction> predictVideoEmotion(File videoFile) {
    throw const VisualLlmException('Visual LLM client is not configured.');
  }
}

class VisualLlmException implements Exception {
  const VisualLlmException(this.message);

  final String message;

  @override
  String toString() => message;
}
