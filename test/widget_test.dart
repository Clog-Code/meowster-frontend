import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:amd_pet_frontend/app/pet_agent_app.dart';
import 'package:amd_pet_frontend/data/services/agent_stream_client.dart';
import 'package:amd_pet_frontend/data/services/location_service.dart';
import 'package:amd_pet_frontend/data/services/pet_box_detector.dart';
import 'package:amd_pet_frontend/data/services/pet_streak_client.dart';
import 'package:amd_pet_frontend/data/services/speech_to_text_service.dart';
import 'package:amd_pet_frontend/data/services/text_to_speech_service.dart';
import 'package:amd_pet_frontend/data/services/visual_llm_client.dart';
import 'package:amd_pet_frontend/domain/models/camera_zoom_state.dart';
import 'package:amd_pet_frontend/domain/models/pet_capture_result.dart';
import 'package:amd_pet_frontend/domain/models/pet_streak_summary.dart';
import 'package:amd_pet_frontend/ui/core/pet_theme.dart';
import 'package:amd_pet_frontend/ui/features/capture/capture_screen.dart';
import 'package:amd_pet_frontend/ui/features/chat/agent_chat_screen.dart';
import 'package:amd_pet_frontend/ui/features/home/views/isometric_home_page.dart';
import 'package:amd_pet_frontend/ui/features/streak/pet_moment_streak_screen.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

Future<void> openCameraFromHome(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('pet-mochi-sprite')));
  await tester.pump();
  await tester.tap(find.byTooltip('Open camera'));
  await tester.pumpAndSettle();
}

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

  test('AgentApiClient stores optional perception token', () {
    final client = AgentApiClient(
      baseUri: Uri.parse('http://localhost:8000'),
      perceptionToken: 'dev-token',
    );

    expect(client.perceptionToken, 'dev-token');
  });

  test('empty todo snapshots do not render HITL cards', () {
    expect(cardFromSnapshot({'todos': []}).isEmpty, isTrue);
    expect(
      cardFromSnapshot({
        'todos': [
          {'content': '   ', 'status': 'pending'},
        ],
      }).isEmpty,
      isTrue,
    );
  });

  test('profile tool results do not render store recommendation cards', () {
    final recommendations = recommendationsFromTools([
      ToolDecoration(
        name: 'get_pet_profile',
        status: ToolStatus.done,
        content:
            '{"name":"Mochi","species":"cat","provider":"owner","known_conditions":"none"}',
      ),
    ]);

    expect(recommendations, isEmpty);
  });

  test('VisualLlmPrediction parses the unified /predict response contract', () {
    final prediction = VisualLlmPrediction.fromJson(const {
      'predicted_emotion': 'sad',
      'confidence': 0.91,
      'is_video': false,
      'detail_breakdown': {
        'angry': 0.01,
        'normal': 0.04,
        'rested': 0.02,
        'sad': 0.91,
        'surprised': 0.02,
      },
    });

    expect(prediction.predictedEmotion, 'sad');
    expect(prediction.confidence, 0.91);
    expect(prediction.isVideo, isFalse);
    expect(prediction.detailBreakdown['sad'], 0.91);
    expect(prediction.allProbabilities['sad'], 0.91);
  });

  test('VisualLlmPrediction still accepts the older probability key', () {
    final prediction = VisualLlmPrediction.fromJson(const {
      'predicted_emotion': 'normal',
      'confidence': 0.82,
      'all_probabilities': {'normal': 0.82, 'sad': 0.18},
    });

    expect(prediction.predictedEmotion, 'normal');
    expect(prediction.isVideo, isFalse);
    expect(prediction.detailBreakdown, {'normal': 0.82, 'sad': 0.18});
  });

  test(
    'VisualLlmApiClient sends videos to /predict_video as video multipart',
    () async {
      final videoFile = File('${Directory.systemTemp.path}/cat_video_test.mp4');
      await videoFile.writeAsBytes(const [0, 1, 2, 3]);
      addTearDown(() {
        if (videoFile.existsSync()) videoFile.deleteSync();
      });

      final client = VisualLlmApiClient(
        baseUri: Uri.parse('http://localhost:8001'),
        client: CapturingHttpClient((request) async {
          expect(request, isA<http.MultipartRequest>());
          final multipart = request as http.MultipartRequest;
          expect(multipart.url.path, '/predict_video');
          expect(multipart.files.single.field, 'file');
          expect(multipart.files.single.contentType.toString(), 'video/mp4');
          return http.Response(
            jsonEncode({
              'predicted_emotion': 'normal',
              'confidence': 0.7143,
              'is_video': true,
              'detail_breakdown': {
                'rested': 0.1429,
                'normal': 0.7143,
                'surprised': 0.1429,
              },
            }),
            200,
          );
        }),
      );

      final prediction = await client.predictVideoEmotion(videoFile);

      expect(prediction.predictedEmotion, 'normal');
      expect(prediction.confidence, 0.7143);
      expect(prediction.isVideo, isTrue);
      expect(prediction.detailBreakdown['normal'], 0.7143);
    },
  );

  test('PetCaptureResult uses visual confidence in perception payloads', () {
    final result = PetCaptureResult(
      kind: CaptureMediaKind.image,
      species: 'cat',
      emotion: 'sad',
      emotionConfidence: 0.91,
      emotionProbabilities: const {'sad': 0.91, 'normal': 0.09},
      healthFlags: const ['visual emotion model'],
      sourceLabel: 'Uploaded image',
      path: '/tmp/cat.jpg',
    );

    final payload = result.toPerceptionPayload('thread-01');

    expect(payload['emotion'], 'sad');
    expect(payload['emotion_confidence'], 0.91);
    expect(payload['emotion_probabilities'], {'sad': 0.91, 'normal': 0.09});
    expect(payload['pet_profile'], isA<Map<String, dynamic>>());
  });

  test('zoom helpers clamp and scale zoom values', () {
    expect(clampZoom(0.2, 1, 5), 1);
    expect(clampZoom(6, 1, 5), 5);
    expect(zoomForScale(baseZoom: 2, scale: 1.5, minZoom: 1, maxZoom: 5), 3);
    expect(zoomForScale(baseZoom: 4, scale: 2, minZoom: 1, maxZoom: 5), 5);
  });

  test('auto tracking zoom converges toward useful pet framing', () {
    expect(
      autoTrackingZoom(
        currentZoom: 1,
        boxAreaFraction: 0.05,
        minZoom: 1,
        maxZoom: 6,
      ),
      greaterThan(1),
    );
    expect(
      autoTrackingZoom(
        currentZoom: 2,
        boxAreaFraction: 0.7,
        minZoom: 1,
        maxZoom: 6,
      ),
      lessThan(2),
    );
    expect(
      autoTrackingZoom(
        currentZoom: 2,
        boxAreaFraction: 0.28,
        minZoom: 1,
        maxZoom: 6,
      ),
      2,
    );
  });

  test('ML Kit rotation compensates Android device orientation', () {
    expect(
      cameraImageRotationDegrees(
        sensorOrientation: 90,
        deviceOrientation: DeviceOrientation.portraitUp,
        lensDirection: CameraLensDirection.back,
        isAndroid: true,
      ),
      90,
    );
    expect(
      cameraImageRotationDegrees(
        sensorOrientation: 90,
        deviceOrientation: DeviceOrientation.landscapeLeft,
        lensDirection: CameraLensDirection.back,
        isAndroid: true,
      ),
      0,
    );
    expect(
      cameraImageRotationDegrees(
        sensorOrientation: 90,
        deviceOrientation: DeviceOrientation.landscapeLeft,
        lensDirection: CameraLensDirection.front,
        isAndroid: true,
      ),
      180,
    );
  });

  test('pet box selection prefers cat labels then best object', () {
    final imageSize = const Size(400, 300);
    final cat = PetBoxCandidate(
      boundingBox: const Rect.fromLTWH(20, 20, 40, 40),
      imageSize: imageSize,
      label: 'Cat',
      confidence: 0.6,
      isCat: true,
    );
    final largerObject = PetBoxCandidate(
      boundingBox: const Rect.fromLTWH(40, 40, 180, 120),
      imageSize: imageSize,
      label: 'Cat candidate',
      confidence: 0.9,
      isCat: false,
    );

    expect(selectBestPetBox([largerObject, cat]), cat);
    expect(selectBestPetBox([largerObject]), largerObject);
  });

  test('pet box tracker clears stale detections', () {
    final tracker = PetBoxTracker(staleAfter: const Duration(seconds: 1));
    final detectedAt = DateTime(2026, 7, 10, 12);
    final candidate = PetBoxCandidate(
      boundingBox: const Rect.fromLTWH(20, 20, 100, 80),
      imageSize: const Size(400, 300),
      label: 'Cat',
      confidence: 0.75,
      isCat: true,
    );

    expect(tracker.update([candidate], now: detectedAt), candidate);
    expect(
      tracker.current(now: detectedAt.add(const Duration(milliseconds: 500))),
      candidate,
    );
    expect(
      tracker.current(now: detectedAt.add(const Duration(seconds: 2))),
      isNull,
    );
  });

  test('PetStreakSummary parses backend streak history', () {
    final summary = PetStreakSummary.fromJson(const {
      'current_streak': 7,
      'longest_streak': 14,
      'month_start': '2026-07-01',
      'days': [
        {
          'date': '2026-07-09',
          'capture_count': 2,
          'dominant_emotion': 'curious',
          'species': 'cat',
        },
        {
          'date': '2026-07-10',
          'capture_count': 1,
          'dominant_emotion': 'distress',
        },
      ],
    });

    expect(summary.currentStreak, 7);
    expect(summary.longestStreak, 14);
    expect(summary.momentsThisMonth, 3);
    expect(summary.capturedDaysInMonth(DateTime(2026, 7)), 2);
    expect(summary.momentsInMonth(DateTime(2026, 7)), 3);
    expect(summary.dayFor(DateTime(2026, 7, 9))?.isHealthy, isTrue);
    expect(summary.dayFor(DateTime(2026, 7, 10))?.isHealthy, isFalse);
  });

  test('DemoPetStreakClient returns rich calendar data', () async {
    final summary = await const DemoPetStreakClient().fetchStreakSummary();

    expect(summary.currentStreak, greaterThan(0));
    expect(summary.longestStreak, greaterThanOrEqualTo(summary.currentStreak));
    expect(summary.days.length, greaterThan(7));
    expect(summary.days.where((day) => day.isHealthy), isNotEmpty);
    expect(
      summary.days.where((day) => day.hasCapture && !day.isHealthy),
      isNotEmpty,
    );
  });

  testWidgets('app opens on the isometric home page', (tester) async {
    await tester.pumpWidget(
      PetAgentApp(
        client: FakeAgentClient(),
        streakClient: FakeStreakClient(),
        enableCamera: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(IsometricHomePage), findsOneWidget);
    expect(find.byKey(const Key('isometric-room-background')), findsOneWidget);
    expect(find.byKey(const Key('isometric-transparent-room')), findsOneWidget);
    expect(find.byKey(const Key('isometric-room-viewer')), findsOneWidget);
    expect(find.text('Pet Moment Streaks'), findsOneWidget);
    expect(find.byType(CaptureScreen), findsNothing);
  });

  testWidgets('capture and replay controls fit a compact phone viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      PetAgentApp(
        client: FakeAgentClient(),
        streakClient: FakeStreakClient(),
        enableCamera: false,
      ),
    );
    await tester.pumpAndSettle();
    await openCameraFromHome(tester);

    expect(find.byKey(const Key('story-shutter')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Demo capture'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('preview-ml-tags')), findsOneWidget);
    expect(find.text('Save Moment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('divider swipe reveals hardware-aware zoom presets', (
    tester,
  ) async {
    await tester.pumpWidget(
      PetAgentApp(
        client: FakeAgentClient(),
        streakClient: FakeStreakClient(),
        enableCamera: false,
      ),
    );
    await tester.pumpAndSettle();
    await openCameraFromHome(tester);

    expect(find.text('.5x'), findsNothing);
    await tester.fling(
      find.byKey(const Key('capture-status-divider')),
      const Offset(0, -100),
      600,
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('.5x'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.text('2x'), findsOneWidget);
    expect(find.text('5x'), findsOneWidget);
    expect(
      tester
          .widget<InkResponse>(find.byKey(const Key('zoom-preset-0.5')))
          .onTap,
      isNull,
    );
    expect(
      tester
          .widget<InkResponse>(find.byKey(const Key('zoom-preset-1.0')))
          .onTap,
      isNotNull,
    );
  });

  testWidgets('pet stat card opens camera and camera returns home', (
    tester,
  ) async {
    await tester.pumpWidget(
      PetAgentApp(
        client: FakeAgentClient(),
        streakClient: FakeStreakClient(),
        enableCamera: false,
      ),
    );
    await tester.pumpAndSettle();

    await openCameraFromHome(tester);
    expect(find.byType(CaptureScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Pet room'));
    await tester.pumpAndSettle();

    expect(find.byType(IsometricHomePage), findsOneWidget);
    expect(find.byType(CaptureScreen), findsNothing);
  });

  testWidgets('pet moment streak pill opens calendar with healthy markers', (
    tester,
  ) async {
    await tester.pumpWidget(
      PetAgentApp(
        client: FakeAgentClient(),
        streakClient: FakeStreakClient(),
        enableCamera: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open pet moment streak calendar'));
    await tester.pumpAndSettle();

    expect(find.text('Pet moment streak'), findsOneWidget);
    expect(find.text('4 day streak'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Weekly view'), 300);
    expect(find.text('Using app'), findsOneWidget);
    expect(find.text('Weekly view'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('July 2026'), 300);
    expect(find.text('July 2026'), findsOneWidget);
    expect(find.text('😺'), findsOneWidget);
    expect(find.text('😿'), findsOneWidget);
    expect(find.text('🐾'), findsWidgets);
  });

  testWidgets('streak calendar navigates between months', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PetTheme.dark(),
        home: PetMomentStreakScreen(
          streakClient: FakeStreakClient(
            summary: PetStreakSummary(
              currentStreak: 4,
              longestStreak: 9,
              monthStart: DateTime(2026, 7),
              days: [
                PetStreakDay(
                  date: DateTime(2026, 7, 7),
                  captureCount: 1,
                  dominantEmotion: 'curious',
                  species: 'cat',
                ),
                PetStreakDay(
                  date: DateTime(2026, 8, 3),
                  captureCount: 2,
                  dominantEmotion: 'happy',
                  species: 'cat',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('July 2026'), 300);
    expect(find.text('July 2026'), findsOneWidget);
    expect(find.text('1/31'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();

    expect(find.text('August 2026'), findsOneWidget);
    expect(find.text('😸'), findsOneWidget);

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    expect(find.text('July 2026'), findsOneWidget);
  });

  testWidgets('moment reel previews a captured cat moment', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PetTheme.dark(),
        home: PetMomentStreakScreen(
          streakClient: FakeStreakClient(
            summary: PetStreakSummary(
              currentStreak: 4,
              longestStreak: 9,
              monthStart: DateTime(2026, 7),
              days: [
                PetStreakDay(
                  date: DateTime(2026, 7, 7),
                  captureCount: 2,
                  dominantEmotion: 'curious',
                  species: 'cat',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Moment reel'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Moment reel'), findsOneWidget);
    expect(find.text('Jul 7'), findsOneWidget);

    await tester.tap(find.text('Jul 7'));
    await tester.pumpAndSettle();

    expect(find.text('July 7, 2026'), findsOneWidget);
    expect(find.text('Healthy moment'), findsOneWidget);
    expect(find.text('2 pet moments'), findsOneWidget);
    expect(find.text('curious'), findsWidgets);
  });

  testWidgets('streak backend failure shows retry without blocking home', (
    tester,
  ) async {
    await tester.pumpWidget(
      PetAgentApp(
        client: FakeAgentClient(),
        streakClient: FakeStreakClient(throwOnFetch: true),
        enableCamera: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(IsometricHomePage), findsOneWidget);

    await tester.tap(find.byTooltip('Open pet moment streak calendar'));
    await tester.pumpAndSettle();

    expect(find.text('Streak history is unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('streak calendar empty state renders retry-free empty calendar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PetTheme.dark(),
        home: PetMomentStreakScreen(
          streakClient: FakeStreakClient(
            summary: PetStreakSummary.empty(monthStart: DateTime(2026, 7)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pet moment streak'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('No pet moments recorded for this month yet.'),
      300,
    );
    expect(
      find.text('No pet moments recorded for this month yet.'),
      findsOneWidget,
    );
  });

  testWidgets('streak calendar fits in a narrow preview viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: PetTheme.dark(),
        home: PetMomentStreakScreen(
          streakClient: FakeStreakClient(
            summary: PetStreakSummary(
              currentStreak: 8,
              longestStreak: 16,
              monthStart: DateTime(2026, 7),
              days: [
                for (var day = 1; day <= 31; day++)
                  PetStreakDay(
                    date: DateTime(2026, 7, day),
                    captureCount: 1,
                    dominantEmotion: day.isEven ? 'curious' : 'watchful',
                    species: 'cat',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Pet moment streak'), findsOneWidget);
    expect(find.text('July 2026'), findsOneWidget);
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

    await tester.pumpWidget(
      PetAgentApp(
        client: client,
        streakClient: FakeStreakClient(),
        textToSpeechService: FakeTextToSpeechService(),
        autoReadPreferenceStore: FakeAutoReadPreferenceStore(enabled: false),
        enableCamera: false,
      ),
    );
    await tester.pump();
    await openCameraFromHome(tester);

    await tester.tap(find.byTooltip('Demo capture'));
    await tester.pumpAndSettle();
    expect(find.text('CAT'), findsOneWidget);
    expect(find.text('DISTRESS'), findsOneWidget);
    expect(find.byKey(const Key('preview-ml-tags')), findsOneWidget);

    await tester.tap(find.text('Ask Agent'));
    await tester.pumpAndSettle();

    expect(client.paths, contains('/perception'));
    expect(client.payloads.last['species'], 'cat');
    expect(client.payloads.last['pet_profile'], isA<Map<String, dynamic>>());
    expect(
      find.textContaining('[perception-event]', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('cat appears distress', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('I can review this pet moment.', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('preview can save moment without opening chat', (tester) async {
    final client = FakeAgentClient();

    await tester.pumpWidget(
      PetAgentApp(
        client: client,
        streakClient: FakeStreakClient(),
        enableCamera: false,
      ),
    );
    await tester.pumpAndSettle();
    await openCameraFromHome(tester);

    await tester.tap(find.byTooltip('Demo capture'));
    await tester.pumpAndSettle();

    expect(find.text('Save Moment'), findsOneWidget);
    expect(find.text('Ask Agent'), findsOneWidget);
    expect(find.text('CAT'), findsOneWidget);
    expect(find.text('DISTRESS'), findsOneWidget);
    expect(find.text('Tracking Unavailable'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Retake')).dy,
      lessThan(tester.getTopLeft(find.text('Save Moment')).dy),
    );
    expect(client.paths, isEmpty);

    await tester.tap(find.text('Save Moment'));
    await tester.pumpAndSettle();

    expect(client.paths, ['/perception']);
    expect(client.payloads.single['emotion'], 'distress');
    expect(find.text('Capture The Pet Moment'), findsOneWidget);
    expect(find.text('SCANNING FOR PET'), findsOneWidget);
    expect(find.byType(AgentChatScreen), findsNothing);
  });

  testWidgets('replay tracking is disabled without captured samples', (
    tester,
  ) async {
    await tester.pumpWidget(
      PetAgentApp(
        client: FakeAgentClient(),
        streakClient: FakeStreakClient(),
        enableCamera: false,
      ),
    );
    await tester.pumpAndSettle();
    await openCameraFromHome(tester);

    await tester.tap(find.byTooltip('Demo capture'));
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('tracking-mode-toggle')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Tracking Unavailable'), findsOneWidget);
    expect(find.text('CAT'), findsOneWidget);
    expect(find.text('DISTRESS'), findsOneWidget);
  });

  testWidgets('predicted image capture sends visual emotion payload', (
    tester,
  ) async {
    final client = FakeAgentClient();
    final capture = PetCaptureResult(
      kind: CaptureMediaKind.image,
      species: 'cat',
      emotion: 'surprised',
      emotionConfidence: 0.77,
      emotionProbabilities: const {'surprised': 0.77, 'normal': 0.23},
      healthFlags: const ['visual emotion model'],
      sourceLabel: 'Uploaded image',
      path: '/tmp/cat.jpg',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: PetTheme.dark(),
        home: AgentChatScreen(
          client: client,
          initialCapture: capture,
          textToSpeechService: FakeTextToSpeechService(),
          autoReadPreferenceStore: FakeAutoReadPreferenceStore(enabled: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(client.paths, contains('/perception'));
    expect(client.payloads.single['emotion'], 'surprised');
    expect(client.payloads.single['emotion_confidence'], 0.77);
    expect(client.payloads.single['emotion_probabilities'], {
      'surprised': 0.77,
      'normal': 0.23,
    });
    expect(
      find.textContaining('cat appears surprised', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('user messages render with the user bubble renderer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PetTheme.dark(),
        home: Scaffold(
          body: UserMessageBubble(
            message: ChatMessage(
              id: 'user-1',
              role: ChatRole.user,
              content: 'My pet is limping',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(UserMessageBubble), findsOneWidget);
    expect(
      find.textContaining('My pet is limping', findRichText: true),
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
          'toolCallId': 'tool-1',
          'toolCallName': 'search_clinics',
        }),
        AgentStreamEvent('TOOL_CALL_ARGS', {
          'type': 'TOOL_CALL_ARGS',
          'toolCallId': 'tool-1',
          'delta': '{"area":"near me","species":"cat"}',
        }),
        AgentStreamEvent('TOOL_CALL_RESULT', {
          'type': 'TOOL_CALL_RESULT',
          'toolCallId': 'tool-1',
          'content':
              '{"summary":"Found 3 clinics.","clinics":[{"name":"Happy Paw Clinic"}]}',
        }),
        AgentStreamEvent('STATE_SNAPSHOT', {
          'type': 'STATE_SNAPSHOT',
          'snapshot': {
            'todos': [
              {'content': 'Check nearby clinics', 'status': 'completed'},
              {'content': 'Ask user for approval', 'status': 'pending'},
              {'content': 'Compare clinic opening hours', 'status': 'pending'},
              {'content': 'Prepare booking options', 'status': 'pending'},
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
        home: AgentChatScreen(
          client: client,
          locationService: const FakeLocationService(),
          textToSpeechService: FakeTextToSpeechService(),
          autoReadPreferenceStore: FakeAutoReadPreferenceStore(enabled: false),
        ),
      ),
    );

    expect(find.byTooltip('Choose media from gallery'), findsOneWidget);
    expect(find.byTooltip('Hold to talk'), findsOneWidget);
    expect(find.byTooltip('Chat menu'), findsOneWidget);

    await tester.tap(find.byTooltip('Chat menu'));
    await tester.pumpAndSettle();

    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Current chat'), findsOneWidget);
    expect(find.text('End current chat'), findsNothing);
    expect(find.text('Capture pet moment'), findsNothing);
    expect(
      find.textContaining('Previous chats will appear here'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'My pet is limping');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(client.paths, contains('/agent'));
    expect(find.text('Agent steps complete'), findsOneWidget);
    expect(find.byTooltip('Copy response'), findsOneWidget);

    await tester.ensureVisible(find.text('Agent steps complete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agent steps complete'));
    await tester.pumpAndSettle();

    expect(find.text('Found 3 clinics.'), findsOneWidget);
    expect(find.text('Happy Paw Clinic'), findsOneWidget);
    expect(find.text('Shop details'), findsOneWidget);
    expect(find.text('Book now'), findsOneWidget);
    expect(find.text('Share current location?'), findsOneWidget);
    expect(find.text('Allow once'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Share current location?')).dy,
      greaterThan(
        tester
            .getTopLeft(
              find.textContaining(
                'The closest clinic is open now.',
                findRichText: true,
              ),
            )
            .dy,
      ),
    );
    expect(find.byTooltip('Agent checklist'), findsOneWidget);

    await tester.tap(find.byTooltip('Agent checklist'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent-checklist-scroll')),
      findsOneWidget,
    );
    expect(find.text('Agent checklist'), findsOneWidget);
    expect(find.text('Check nearby clinics'), findsOneWidget);
    expect(find.text('Compare clinic opening hours'), findsOneWidget);
    expect(find.text('Prepare booking options'), findsNothing);
    expect(find.text('Show 1 more'), findsOneWidget);
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
    expect(find.text('Done'), findsNothing);

    await tester.tap(find.text('Show 1 more'));
    await tester.pumpAndSettle();

    expect(find.text('Prepare booking options'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Allow once'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow once'));
    await tester.pumpAndSettle();

    expect(client.paths.where((path) => path == '/agent'), hasLength(1));
    expect(find.text('Location saved for your next reply.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '4.2 kg, no known medical conditions',
    );
    await tester.ensureVisible(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(client.paths.where((path) => path == '/agent'), hasLength(2));
    final locationPayload = client.payloads.last;
    final context = locationPayload['context'] as List<dynamic>;
    expect(context, hasLength(2));
    expect(context.first, containsPair('description', isA<String>()));
    expect(context.first, containsPair('value', isA<String>()));
    expect(context.last, containsPair('description', isA<String>()));
    expect(context.last, containsPair('value', isA<String>()));
    expect(context.last['value'], contains('3.123456'));
    expect(context.last['value'], contains('101.654321'));
    final messages = locationPayload['messages'] as List<dynamic>;
    expect(messages.last['content'], contains('4.2 kg'));
    expect(messages.last['content'], contains('[location-context]'));
    expect(messages.last['content'], contains('3.123456'));
  });

  testWidgets('composer expands upward for multiline text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(340, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: PetTheme.dark(),
        home: AgentChatScreen(
          client: FakeAgentClient(),
          textToSpeechService: FakeTextToSpeechService(),
          autoReadPreferenceStore: FakeAutoReadPreferenceStore(enabled: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textField = find.byKey(const ValueKey('chat-text-field'));
    final initialTop = tester.getTopLeft(textField).dy;
    await tester.enterText(
      textField,
      'Line one\nLine two\nLine three\nLine four\nLine five\nLine six',
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(textField).dy, lessThan(initialTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'push-to-talk shows waveform and preserves transcript on release',
    (tester) async {
      final speech = FakeSpeechToTextService();

      await tester.pumpWidget(
        MaterialApp(
          theme: PetTheme.dark(),
          home: AgentChatScreen(
            client: FakeAgentClient(),
            speechToTextService: speech,
            textToSpeechService: FakeTextToSpeechService(),
            autoReadPreferenceStore: FakeAutoReadPreferenceStore(
              enabled: false,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'My cat is');
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('push-to-talk-button'))),
      );
      await tester.pump(const Duration(milliseconds: 750));

      expect(speech.listenCount, 1);
      expect(find.byTooltip('Release to stop dictation'), findsOneWidget);
      expect(find.byKey(const ValueKey('voice-waveform')), findsOneWidget);

      speech.emit('limping today');
      speech.emitSoundLevel(0.82);
      await tester.pump();

      final liveTranscript = tester.widget<Text>(
        find.byKey(const ValueKey('live-transcript')),
      );
      expect(liveTranscript.data, 'My cat is limping today');

      await gesture.up();
      await tester.pumpAndSettle();

      expect(speech.stopCount, 1);
      expect(find.byTooltip('Hold to talk'), findsOneWidget);
      final textField = tester.widget<TextField>(
        find.byKey(const ValueKey('chat-text-field')),
      );
      expect(textField.controller!.text, 'My cat is limping today');
    },
  );

  testWidgets('dictation error keeps typed input and shows snackbar', (
    tester,
  ) async {
    final speech = FakeSpeechToTextService(
      error: const SpeechToTextServiceException(
        'Speech permission was not granted.',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: PetTheme.dark(),
        home: AgentChatScreen(
          client: FakeAgentClient(),
          speechToTextService: speech,
          textToSpeechService: FakeTextToSpeechService(),
          autoReadPreferenceStore: FakeAutoReadPreferenceStore(enabled: false),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Keep this text');
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('push-to-talk-button'))),
    );
    await tester.pump(const Duration(milliseconds: 750));
    await gesture.up();
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, 'Keep this text');
    expect(
      find.text('Microphone or speech permission was not granted.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Hold to talk'), findsOneWidget);
  });

  testWidgets('sending after dictation posts transcript message', (
    tester,
  ) async {
    final client = FakeAgentClient();
    final speech = FakeSpeechToTextService();

    await tester.pumpWidget(
      MaterialApp(
        theme: PetTheme.dark(),
        home: AgentChatScreen(
          client: client,
          speechToTextService: speech,
          textToSpeechService: FakeTextToSpeechService(),
          autoReadPreferenceStore: FakeAutoReadPreferenceStore(enabled: false),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('push-to-talk-button'))),
    );
    await tester.pump(const Duration(milliseconds: 750));
    speech.emit('My cat has watery eyes');
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(client.paths, contains('/agent'));
    final messages = client.payloads.last['messages'] as List<dynamic>;
    expect(messages.last['content'], 'My cat has watery eyes');
  });

  testWidgets('runtime speech errors close waveform without clearing draft', (
    tester,
  ) async {
    final speech = FakeSpeechToTextService();
    await tester.pumpWidget(
      MaterialApp(
        theme: PetTheme.dark(),
        home: AgentChatScreen(
          client: FakeAgentClient(),
          speechToTextService: speech,
          textToSpeechService: FakeTextToSpeechService(),
          autoReadPreferenceStore: FakeAutoReadPreferenceStore(enabled: false),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Keep me');
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('push-to-talk-button'))),
    );
    await tester.pump(const Duration(milliseconds: 750));
    speech.emit('and this');
    await tester.pump();
    speech.emitRuntimeError(
      const SpeechToTextServiceException('Recognizer became unavailable.'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('voice-waveform')), findsNothing);
    expect(find.text('Recognizer became unavailable.'), findsOneWidget);
    final textField = tester.widget<TextField>(
      find.byKey(const ValueKey('chat-text-field')),
    );
    expect(textField.controller!.text, 'Keep me and this');
    await gesture.up();
  });

  testWidgets('completed answers auto-read and speaker action persists mute', (
    tester,
  ) async {
    final tts = FakeTextToSpeechService();
    final preferences = FakeAutoReadPreferenceStore(enabled: true);
    final client = FakeAgentClient(
      events: const [
        AgentStreamEvent('TEXT_MESSAGE_START', {'type': 'TEXT_MESSAGE_START'}),
        AgentStreamEvent('TEXT_MESSAGE_CONTENT', {
          'type': 'TEXT_MESSAGE_CONTENT',
          'delta': 'Keep your cat hydrated.',
        }),
        AgentStreamEvent('TEXT_MESSAGE_END', {'type': 'TEXT_MESSAGE_END'}),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: PetTheme.dark(),
        home: AgentChatScreen(
          client: client,
          textToSpeechService: tts,
          autoReadPreferenceStore: preferences,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'What should I do?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(tts.spokenTexts, ['Keep your cat hydrated.']);
    expect(find.byTooltip('Mute auto-read'), findsOneWidget);

    await tester.tap(find.byTooltip('Mute auto-read'));
    await tester.pumpAndSettle();
    expect(preferences.writes, [false]);
    expect(find.byTooltip('Read response aloud'), findsOneWidget);

    await tester.tap(find.byTooltip('Read response aloud'));
    await tester.pumpAndSettle();
    expect(preferences.writes, [false, true]);
    expect(tts.spokenTexts, [
      'Keep your cat hydrated.',
      'Keep your cat hydrated.',
    ]);
  });

  testWidgets('TTS failure leaves assistant answer visible', (tester) async {
    final client = FakeAgentClient(
      events: const [
        AgentStreamEvent('TEXT_MESSAGE_START', {'type': 'TEXT_MESSAGE_START'}),
        AgentStreamEvent('TEXT_MESSAGE_CONTENT', {
          'type': 'TEXT_MESSAGE_CONTENT',
          'delta': 'Monitor appetite overnight.',
        }),
        AgentStreamEvent('TEXT_MESSAGE_END', {'type': 'TEXT_MESSAGE_END'}),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: PetTheme.dark(),
        home: AgentChatScreen(
          client: client,
          textToSpeechService: FakeTextToSpeechService(
            error: const TextToSpeechException('Connection refused'),
          ),
          autoReadPreferenceStore: FakeAutoReadPreferenceStore(enabled: true),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Help');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Monitor appetite overnight.', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Voice playback is unavailable.'),
      findsOneWidget,
    );
  });

  testWidgets('long agent checklist scrolls to expanded final todo', (
    tester,
  ) async {
    final client = FakeAgentClient(
      events: [
        AgentStreamEvent('STATE_SNAPSHOT', {
          'type': 'STATE_SNAPSHOT',
          'snapshot': {
            'todos': [
              for (var index = 1; index <= 16; index++)
                {'content': 'Care task $index', 'status': 'pending'},
            ],
          },
        }),
        const AgentStreamEvent('TEXT_MESSAGE_START', {
          'type': 'TEXT_MESSAGE_START',
        }),
        const AgentStreamEvent('TEXT_MESSAGE_CONTENT', {
          'type': 'TEXT_MESSAGE_CONTENT',
          'delta': 'I prepared the care checklist.',
        }),
        const AgentStreamEvent('TEXT_MESSAGE_END', {
          'type': 'TEXT_MESSAGE_END',
        }),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: PetTheme.dark(),
        home: AgentChatScreen(
          client: client,
          textToSpeechService: FakeTextToSpeechService(),
          autoReadPreferenceStore: FakeAutoReadPreferenceStore(enabled: false),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Create a checklist');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Agent checklist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show 13 more'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Care task 16'),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('agent-checklist-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    expect(find.text('Care task 16'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
        home: AgentChatScreen(
          client: client,
          textToSpeechService: FakeTextToSpeechService(),
          autoReadPreferenceStore: FakeAutoReadPreferenceStore(enabled: false),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Help');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('partial answer', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('Connection issue:', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('network failed'), findsWidgets);
  });
}

class FakeLocationService implements LocationService {
  const FakeLocationService();

  @override
  Future<PetAgentLocation> requestCurrentLocation() async {
    return PetAgentLocation(
      latitude: 3.123456,
      longitude: 101.654321,
      accuracyMeters: 12,
      timestamp: DateTime(2026, 7, 9, 12),
    );
  }
}

class FakeSpeechToTextService implements SpeechToTextService {
  FakeSpeechToTextService({this.error});

  final Object? error;
  SpeechTranscriptCallback? _onResult;
  SpeechListeningChanged? _onListeningChanged;
  SpeechSoundLevelChanged? _onSoundLevelChanged;
  SpeechRecognitionFailed? _onError;
  int listenCount = 0;
  int stopCount = 0;
  int cancelCount = 0;

  @override
  Future<void> listen({
    required SpeechTranscriptCallback onResult,
    SpeechListeningChanged? onListeningChanged,
    SpeechSoundLevelChanged? onSoundLevelChanged,
    SpeechRecognitionFailed? onError,
  }) async {
    listenCount += 1;
    if (error != null) throw error!;
    _onResult = onResult;
    _onListeningChanged = onListeningChanged;
    _onSoundLevelChanged = onSoundLevelChanged;
    _onError = onError;
    _onListeningChanged?.call(true);
  }

  void emit(String transcript, {bool isFinal = false}) {
    _onResult?.call(transcript, isFinal);
  }

  void emitSoundLevel(double level) => _onSoundLevelChanged?.call(level);

  void emitRuntimeError(Object error) => _onError?.call(error);

  @override
  Future<void> stop() async {
    stopCount += 1;
    _onListeningChanged?.call(false);
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
    _onListeningChanged?.call(false);
  }
}

class FakeTextToSpeechService implements TextToSpeechService {
  FakeTextToSpeechService({this.error});

  final Object? error;
  final spokenTexts = <String>[];
  int stopCount = 0;
  int disposeCount = 0;

  @override
  Future<void> speak(String text) async {
    spokenTexts.add(text);
    if (error != null) throw error!;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

class FakeAutoReadPreferenceStore implements AutoReadPreferenceStore {
  FakeAutoReadPreferenceStore({required this.enabled});

  bool enabled;
  int readCount = 0;
  final writes = <bool>[];

  @override
  Future<bool> readEnabled() async {
    readCount += 1;
    return enabled;
  }

  @override
  Future<void> writeEnabled(bool enabled) async {
    this.enabled = enabled;
    writes.add(enabled);
  }
}

class FakeStreakClient implements PetStreakClient {
  FakeStreakClient({PetStreakSummary? summary, this.throwOnFetch = false})
    : summary =
          summary ??
          PetStreakSummary(
            currentStreak: 4,
            longestStreak: 9,
            monthStart: DateTime(2026, 7),
            days: [
              PetStreakDay(
                date: DateTime(2026, 7, 7),
                captureCount: 1,
                dominantEmotion: 'curious',
                species: 'cat',
              ),
              PetStreakDay(
                date: DateTime(2026, 7, 8),
                captureCount: 1,
                dominantEmotion: 'distress',
                species: 'cat',
              ),
            ],
          );

  final PetStreakSummary summary;
  final bool throwOnFetch;
  int fetchCount = 0;

  @override
  Future<PetStreakSummary> fetchStreakSummary({String petId = 'pet-01'}) async {
    fetchCount += 1;
    if (throwOnFetch) throw StateError('streak unavailable');
    return summary;
  }
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

  @override
  Future<UploadedMedia> uploadMedia(File file) async {
    return UploadedMedia(url: '', path: file.path);
  }

  @override
  Future<List<ChatThreadSummary>> fetchThreads({int limit = 50}) async {
    return [];
  }

  @override
  Future<List<ChatMessage>> fetchThreadMessages(String threadId) async {
    return [];
  }
}

class CapturingHttpClient extends http.BaseClient {
  CapturingHttpClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }
}
