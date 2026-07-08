import 'package:amd_pet_frontend/app/pet_agent_app.dart';
import 'package:amd_pet_frontend/data/services/agent_stream_client.dart';
import 'package:amd_pet_frontend/ui/core/pet_theme.dart';
import 'package:amd_pet_frontend/ui/features/chat/agent_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AgentSseParser handles split chunks and malformed events', () {
    final parser = AgentSseParser();

    expect(parser.addChunk('data: {"type":"TEXT_MESSAGE_STA'), isEmpty);

    final events = parser.addChunk(
      'RT"}\n\n'
      'data: not-json\n\n'
      'data: {"type":"TEXT_MESSAGE_CONTENT","delta":"hello"}\n\n'
      'data: {"type":"RUN_ERROR","message":"failed"}\n\n',
    );

    expect(events, hasLength(3));
    expect(events[0].type, 'TEXT_MESSAGE_START');
    expect(events[1].type, 'TEXT_MESSAGE_CONTENT');
    expect(events[1].data['delta'], 'hello');
    expect(events[2].type, 'RUN_ERROR');
    expect(events[2].data['message'], 'failed');
  });

  testWidgets('app opens on the capture page with fallback camera UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      PetAgentApp(client: FakeAgentClient(), enableCamera: false),
    );
    await tester.pump();

    expect(find.text('Capture The Pet Moment'), findsOneWidget);
    expect(find.text('Pet moment'), findsOneWidget);
    expect(find.byTooltip('Upload picture'), findsOneWidget);
  });

  testWidgets('demo capture transitions to chat and sends perception', (
    tester,
  ) async {
    final client = FakeAgentClient();
    client.events = [
      const AgentStreamEvent('TEXT_MESSAGE_START', {
        'type': 'TEXT_MESSAGE_START',
      }),
      const AgentStreamEvent('TEXT_MESSAGE_CONTENT', {
        'type': 'TEXT_MESSAGE_CONTENT',
        'delta': 'I can review this pet moment.',
      }),
      const AgentStreamEvent('TEXT_MESSAGE_END', {'type': 'TEXT_MESSAGE_END'}),
    ];

    await tester.pumpWidget(PetAgentApp(client: client, enableCamera: false));
    await tester.pump();

    await tester.tap(find.byTooltip('Demo capture'));
    await tester.pumpAndSettle();
    expect(find.text('Ready For Agent Review'), findsOneWidget);

    await tester.tap(find.text('Ask Agent'));
    await tester.pumpAndSettle();

    expect(client.paths, contains('/perception'));
    expect(client.payloads.single['species'], 'cat');
    expect(
      find.textContaining('[perception-event]', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('I can review this pet moment.', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('chat renders input bar, tool timeline, and HITL checklist', (
    tester,
  ) async {
    final client = FakeAgentClient(
      events: const [
        AgentStreamEvent('TOOL_CALL_START', {
          'type': 'TOOL_CALL_START',
          'toolCallName': 'search_clinics',
        }),
        AgentStreamEvent('TOOL_CALL_RESULT', {
          'type': 'TOOL_CALL_RESULT',
          'content': 'Found 3 clinics.',
        }),
        AgentStreamEvent('STATE_SNAPSHOT', {
          'type': 'STATE_SNAPSHOT',
          'snapshot': {
            'todos': [
              {'content': 'Check nearby clinics', 'status': 'completed'},
              {'content': 'Ask user for approval', 'status': 'pending'},
            ],
          },
        }),
        AgentStreamEvent('TEXT_MESSAGE_START', {'type': 'TEXT_MESSAGE_START'}),
        AgentStreamEvent('TEXT_MESSAGE_CONTENT', {
          'type': 'TEXT_MESSAGE_CONTENT',
          'delta': 'The closest clinic is open now.',
        }),
        AgentStreamEvent('TEXT_MESSAGE_END', {'type': 'TEXT_MESSAGE_END'}),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: PetTheme.dark(),
        home: AgentChatScreen(client: client),
      ),
    );

    expect(find.byTooltip('Camera or gallery'), findsOneWidget);
    expect(find.byTooltip('Voice call'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'My pet is limping');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(client.paths, contains('/agent'));
    expect(find.text('Found 3 clinics.'), findsOneWidget);
    expect(find.text('Agent checklist'), findsOneWidget);
    expect(find.text('Check nearby clinics'), findsOneWidget);
    expect(
      find.textContaining(
        'The closest clinic is open now.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Modify'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('broken stream removes incomplete assistant bubble', (
    tester,
  ) async {
    final client = FakeAgentClient(
      events: const [
        AgentStreamEvent('TEXT_MESSAGE_START', {'type': 'TEXT_MESSAGE_START'}),
        AgentStreamEvent('TEXT_MESSAGE_CONTENT', {
          'type': 'TEXT_MESSAGE_CONTENT',
          'delta': 'partial answer',
        }),
      ],
      throwAfterEvents: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: PetTheme.dark(),
        home: AgentChatScreen(client: client),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Help');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('partial answer', findRichText: true),
      findsNothing,
    );
    expect(find.text('Network unstable. Please try again.'), findsOneWidget);
  });
}

class FakeAgentClient implements AgentStreamClient {
  FakeAgentClient({this.events = const [], this.throwAfterEvents = false});

  List<AgentStreamEvent> events;
  final bool throwAfterEvents;
  final paths = <String>[];
  final payloads = <Map<String, dynamic>>[];

  @override
  Future<void> streamAgent({
    required String path,
    required Map<String, dynamic> payload,
    required void Function(AgentStreamEvent event) onEvent,
  }) async {
    paths.add(path);
    payloads.add(payload);
    for (final event in events) {
      onEvent(event);
      await Future<void>.delayed(Duration.zero);
    }
    if (throwAfterEvents) {
      throw StateError('network failed');
    }
  }
}
