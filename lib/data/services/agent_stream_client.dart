import 'dart:convert';
import 'dart:io';

enum ChatRole { user, assistant, system }

enum ToolStatus { running, done }

class ToolDecoration {
  ToolDecoration({required this.name, required this.status, this.content = ''});

  final String name;
  ToolStatus status;
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
    this.attachmentLabel,
    List<ToolDecoration>? tools,
    this.hitlCard,
    this.isStreaming = false,
    this.isError = false,
  }) : tools = tools ?? [];

  final String id;
  final ChatRole role;
  String content;
  String? attachmentLabel;
  final List<ToolDecoration> tools;
  HitlCardData? hitlCard;
  bool isStreaming;
  bool isError;
}

class AgentStreamEvent {
  const AgentStreamEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;
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

abstract class AgentStreamClient {
  Future<void> streamAgent({
    required String path,
    required Map<String, dynamic> payload,
    required void Function(AgentStreamEvent event) onEvent,
  });
}

class AgentApiClient implements AgentStreamClient {
  AgentApiClient({required this.baseUri});

  factory AgentApiClient.fromEnvironment() {
    const configured = String.fromEnvironment(
      'AGENT_BASE_URL',
      defaultValue: 'http://localhost:8000',
    );
    return AgentApiClient(baseUri: Uri.parse(configured));
  }

  final Uri baseUri;

  @override
  Future<void> streamAgent({
    required String path,
    required Map<String, dynamic> payload,
    required void Function(AgentStreamEvent event) onEvent,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(baseUri.resolve(path));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.write(jsonEncode(payload));

      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Request failed: ${response.statusCode}');
      }

      final parser = AgentSseParser();
      await for (final chunk in response.transform(utf8.decoder)) {
        for (final event in parser.addChunk(chunk)) {
          onEvent(event);
        }
      }
    } finally {
      client.close();
    }
  }
}

Map<String, dynamic> buildRunAgentInput({
  required String threadId,
  required String runId,
  required List<ChatMessage> messages,
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
            'content': message.content,
          },
        )
        .toList(),
    'tools': [],
    'context': [],
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
    return HitlCardData(
      title: 'Agent checklist',
      body: 'The agent is working through these steps.',
      todos: todos.map((todo) {
        if (todo is Map<String, dynamic>) {
          return HitlTodo(
            content: todo['content']?.toString() ?? 'Task',
            completed: todo['status']?.toString() == 'completed',
          );
        }
        return HitlTodo(content: todo.toString(), completed: false);
      }).toList(),
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
