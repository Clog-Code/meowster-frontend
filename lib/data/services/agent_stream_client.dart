import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/models/pet_capture_result.dart';

/// Result of uploading a media file to the agentic backend's `/upload`
/// endpoint. `path` is the server-side absolute disk path — this is what
/// the backend's `visual_search` tool expects as `image_path` (it publishes
/// the file to a temporary public host itself before calling Google Lens),
/// so callers should thread `path`, not `url`, into anything that needs to
/// trigger a visual search.
class UploadedMedia {
  const UploadedMedia({required this.url, required this.path, this.filename});

  final String url;
  final String path;
  final String? filename;

  factory UploadedMedia.fromJson(Map<String, dynamic> json) {
    return UploadedMedia(
      url: json['url']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      filename: json['filename']?.toString(),
    );
  }
}

class MediaUploadException implements Exception {
  const MediaUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum ChatRole { user, assistant, system }

enum ToolStatus { running, done }

class ToolDecoration {
  ToolDecoration({
    required this.name,
    required this.status,
    this.id,
    this.args = '',
    this.content = '',
  });

  final String? id;
  final String name;
  ToolStatus status;
  String args;
  String content;
}

class HitlCardData {
  const HitlCardData({
    required this.title,
    required this.body,
    this.todos = const [],
    this.payloadPreview,
  });

  final String title;
  final String body;
  final List<HitlTodo> todos;
  final String? payloadPreview;

  bool get isEmpty =>
      todos.isEmpty && body.trim().isEmpty && payloadPreview == null;
}

class HitlTodo {
  const HitlTodo({required this.content, required this.completed});

  final String content;
  final bool completed;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    this.content = '',
    this.agentContext,
    this.attachmentLabel,
    this.capture,
    this.localImagePath,
    List<ToolDecoration>? tools,
    this.hitlCard,
    this.isStreaming = false,
    this.isError = false,
  }) : tools = tools ?? [];

  final String id;
  final ChatRole role;
  String content;
  String? agentContext;
  String? attachmentLabel;
  PetCaptureResult? capture;

  /// On-device path of a photo attached via the lightweight chat-page
  /// "attach a photo + type a message" flow (as opposed to [capture],
  /// which carries a full on-device ML perception result from the
  /// snapchat-style camera screen). Only used to render a thumbnail in
  /// the user's own chat bubble — the server-side path this refers to is
  /// threaded into [agentContext] instead, for the agent's `visual_search`
  /// tool to pick up.
  String? localImagePath;
  final List<ToolDecoration> tools;
  HitlCardData? hitlCard;
  bool isStreaming;
  bool isError;

  /// Once true, the agent-action-leak heuristic is no longer applied to
  /// this message. Without this, a message that grows long enough to
  /// coincidentally contain leak-like substrings (e.g. a normal reply that
  /// happens to mention both "todos" and "status") would have its entire
  /// accumulated content wiped mid-stream, producing a visible glitch where
  /// text flashes and disappears. The check is only meaningful while the
  /// message is still short enough to plausibly *be* a raw leaked payload.
  bool leakCheckResolved = false;
}

class AgentStreamEvent {
  const AgentStreamEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;
}

class AgentConnectionException implements Exception {
  const AgentConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AgentSseParser {
  final StringBuffer _buffer = StringBuffer();

  List<AgentStreamEvent> addChunk(String chunk) {
    _buffer.write(chunk);
    final text = _buffer.toString();
    final blocks = text.split('\n\n');
    _buffer
      ..clear()
      ..write(blocks.removeLast());

    final parsed = <AgentStreamEvent>[];
    for (final raw in blocks) {
      final dataLines = raw
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.startsWith('data:'))
          .map((line) => line.substring('data:'.length).trim())
          .where((line) => line.isNotEmpty);

      for (final jsonLine in dataLines) {
        try {
          final decoded = jsonDecode(jsonLine);
          if (decoded is Map<String, dynamic>) {
            final type = decoded['type'];
            if (type is String) parsed.add(AgentStreamEvent(type, decoded));
          }
        } on FormatException {
          // Match the backend team's JS harness: malformed SSE events are ignored.
        }
      }
    }
    return parsed;
  }
}

class ChatThreadSummary {
  ChatThreadSummary({
    required this.threadId,
    this.title,
    required this.createdAt,
    required this.messageCount,
    this.lastMessage,
    this.lastMessageAt,
  });

  factory ChatThreadSummary.fromJson(Map<String, dynamic> json) {
    return ChatThreadSummary(
      threadId: json['thread_id']?.toString() ?? '',
      title: json['title']?.toString(),
      createdAt: json['created_at']?.toString() ?? '',
      messageCount: json['message_count'] is int
          ? json['message_count'] as int
          : int.tryParse(json['message_count']?.toString() ?? '0') ?? 0,
      lastMessage: json['last_message']?.toString(),
      lastMessageAt: json['last_message_at']?.toString(),
    );
  }

  final String threadId;
  final String? title;
  final String createdAt;
  final int messageCount;
  final String? lastMessage;
  final String? lastMessageAt;
}

abstract class AgentStreamClient {
  Future<void> streamAgent({
    required String path,
    required Map<String, dynamic> payload,
    required void Function(AgentStreamEvent event) onEvent,
  });

  /// Uploads a photo/video to the agentic backend's `POST /upload` so it
  /// can be referenced (by server-side path) from a chat/perception message
  /// — this is what lets a subagent's `visual_search` tool pick it up.
  Future<UploadedMedia> uploadMedia(File file);

  /// Fetch recently active conversation threads for a "recent chats" list.
  Future<List<ChatThreadSummary>> fetchThreads({int limit = 50});

  /// Fetch the full ordered message history for a thread (for restoring a
  /// conversation after reopening the app or switching threads).
  Future<List<ChatMessage>> fetchThreadMessages(String threadId);

  /// Fetch a pet's profile from the backend.
  Future<Map<String, dynamic>?> fetchPetProfile(String petId);
}

class AgentApiClient implements AgentStreamClient {
  AgentApiClient({required this.baseUri, this.perceptionToken = ''});

  factory AgentApiClient.fromEnvironment() {
    const configured = String.fromEnvironment(
      'AGENT_BASE_URL',
      defaultValue: 'http://localhost:8000',
    );
    const perceptionToken = String.fromEnvironment('AGENT_PERCEPTION_TOKEN');
    return AgentApiClient(
      baseUri: Uri.parse(configured),
      perceptionToken: perceptionToken,
    );
  }

  final Uri baseUri;
  final String perceptionToken;

  @override
  Future<void> streamAgent({
    required String path,
    required Map<String, dynamic> payload,
    required void Function(AgentStreamEvent event) onEvent,
  }) async {
    final client = HttpClient();
    final uri = baseUri.resolve(path);
    client.connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      if (path == '/perception' && perceptionToken.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $perceptionToken',
        );
      }
      request.write(jsonEncode(payload));

      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.transform(utf8.decoder).join();
        final detail = body.trim().isEmpty ? '' : ': ${body.trim()}';
        throw AgentConnectionException(
          'Backend request failed (${response.statusCode}) at $uri$detail',
        );
      }

      final parser = AgentSseParser();
      try {
        await for (final chunk in response.transform(utf8.decoder)) {
          for (final event in parser.addChunk(chunk)) {
            onEvent(event);
          }
        }
      } on Object catch (error) {
        throw AgentConnectionException(
          'Backend stream disconnected at $uri: $error',
        );
      }
    } on AgentConnectionException {
      rethrow;
    } on SocketException catch (error) {
      throw AgentConnectionException('Could not connect to $uri: $error');
    } finally {
      client.close();
    }
  }

  @override
  Future<UploadedMedia> uploadMedia(File file) async {
    final uri = baseUri.resolve('/upload');
    try {
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('file', file.path));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = response.body.trim().isEmpty
            ? ''
            : ': ${response.body.trim()}';
        throw MediaUploadException(
          'Upload failed (${response.statusCode}) at $uri$detail',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const MediaUploadException('Upload response must be a JSON object');
      }
      return UploadedMedia.fromJson(decoded);
    } on MediaUploadException {
      rethrow;
    } on SocketException catch (error) {
      throw MediaUploadException('Could not connect to $uri: $error');
    } on Object catch (error) {
      throw MediaUploadException('Upload failed at $uri: $error');
    }
  }

  @override
  Future<List<ChatThreadSummary>> fetchThreads({int limit = 50}) async {
    final uri = baseUri.replace(queryParameters: {'limit': limit.toString()});
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri.resolve('/threads'));
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AgentConnectionException(
          'Failed to fetch threads (${response.statusCode}): $body',
        );
      }
      final decoded = jsonDecode(body);
      final list = (decoded is Map ? decoded['threads'] : null) as List?;
      if (list == null) return [];
      return list
          .map((e) => ChatThreadSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } on SocketException catch (error) {
      throw AgentConnectionException('Could not connect to $uri: $error');
    } finally {
      client.close();
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchPetProfile(String petId) async {
    final uri = baseUri.resolve('/pet-profile/$petId');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 404) return null;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AgentConnectionException(
          'Failed to fetch pet profile (${response.statusCode}): $body',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded['profile'] is Map) {
        return decoded['profile'] as Map<String, dynamic>;
      }
      return null;
    } on SocketException catch (error) {
      throw AgentConnectionException('Could not connect to $uri: $error');
    } finally {
      client.close();
    }
  }

  @override
  Future<List<ChatMessage>> fetchThreadMessages(String threadId) async {
    final uri = baseUri.resolve('/threads/$threadId/messages');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AgentConnectionException(
          'Failed to fetch messages (${response.statusCode}): $body',
        );
      }
      final decoded = jsonDecode(body);
      final list = (decoded is Map ? decoded['messages'] : null) as List?;
      if (list == null) return [];
      return list.map((e) {
        final item = e as Map<String, dynamic>;
        final roleStr = item['role']?.toString() ?? 'user';
        return ChatMessage(
          id: item['message_id']?.toString() ?? '',
          role: roleStr == 'assistant' ? ChatRole.assistant : ChatRole.user,
          content: item['content']?.toString() ?? '',
        );
      }).toList();
    } on SocketException catch (error) {
      throw AgentConnectionException('Could not connect to $uri: $error');
    } finally {
      client.close();
    }
  }
}

Map<String, dynamic> buildRunAgentInput({
  required String threadId,
  required String runId,
  required List<ChatMessage> messages,
  List<Map<String, dynamic>> context = const [],
}) {
  return {
    'threadId': threadId,
    'runId': runId,
    'state': <String, dynamic>{},
    'messages': messages
        .where(
          (message) =>
              message.role == ChatRole.user ||
              (message.role == ChatRole.assistant &&
                  message.content.isNotEmpty),
        )
        .map(
          (message) => {
            'id': message.id,
            'role': message.role == ChatRole.user ? 'user' : 'assistant',
            'content': [
              message.content,
              if (message.agentContext != null) message.agentContext!,
            ].where((part) => part.trim().isNotEmpty).join('\n\n'),
          },
        )
        .toList(),
    'tools': [],
    'context': context,
    'forwardedProps': {},
  };
}

HitlCardData cardFromSnapshot(Object? snapshot) {
  if (snapshot is! Map<String, dynamic>) {
    return const HitlCardData(
      title: 'Action needed',
      body: 'The agent needs your approval to continue.',
    );
  }

  final todos = snapshot['todos'];
  if (todos is List) {
    final parsedTodos = todos
        .map((todo) {
          if (todo is Map<String, dynamic>) {
            final content = todo['content']?.toString().trim() ?? '';
            if (content.isEmpty) return null;
            return HitlTodo(
              content: content,
              completed: todo['status']?.toString() == 'completed',
            );
          }
          final content = todo.toString().trim();
          if (content.isEmpty) return null;
          return HitlTodo(content: content, completed: false);
        })
        .nonNulls
        .toList();

    return HitlCardData(
      title: 'Agent checklist',
      body: parsedTodos.isEmpty
          ? ''
          : 'The agent is working through these steps.',
      todos: parsedTodos,
    );
  }

  final action =
      snapshot['action']?.toString() ?? snapshot['title']?.toString();
  final payload =
      snapshot['payload'] ?? snapshot['message'] ?? snapshot['request'];
  return HitlCardData(
    title: action == null ? 'Action approval' : 'Approve $action?',
    body:
        snapshot['description']?.toString() ??
        snapshot['details']?.toString() ??
        'Review this action before the agent continues.',
    payloadPreview: payload == null
        ? null
        : const JsonEncoder.withIndent('  ').convert(payload),
  );
}

String newAgentId() => DateTime.now().microsecondsSinceEpoch.toString();