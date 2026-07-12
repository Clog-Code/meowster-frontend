import 'package:flutter/material.dart';

import '../data/services/agent_stream_client.dart';
import '../data/services/pet_box_detector.dart';
import '../data/services/pet_streak_client.dart';
import '../data/services/text_to_speech_service.dart';
import '../data/services/visual_llm_client.dart';
import '../ui/core/pet_theme.dart';
import '../ui/features/capture/capture_screen.dart';
import '../ui/features/chat/agent_chat_screen.dart';
import '../ui/features/home/views/isometric_home_page.dart';
import '../ui/features/streak/pet_moment_streak_screen.dart';

class PetAgentApp extends StatelessWidget {
  const PetAgentApp({
    required this.client,
    required this.streakClient,
    this.visualLlmClient = const DisabledVisualLlmClient(),
    this.petBoxDetector,
    this.textToSpeechService,
    this.autoReadPreferenceStore,
    this.enableCamera = true,
    super.key,
  });

  final AgentStreamClient client;
  final PetStreakClient streakClient;
  final VisualLlmClient visualLlmClient;
  final PetBoxDetector? petBoxDetector;
  final TextToSpeechService? textToSpeechService;
  final AutoReadPreferenceStore? autoReadPreferenceStore;
  final bool enableCamera;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pet Agent',
      debugShowCheckedModeBanner: false,
      theme: PetTheme.dark(),
      home: IsometricHomePage(
        captureScreenBuilder: (context) => CaptureScreen(
          client: client,
          streakClient: streakClient,
          visualLlmClient: visualLlmClient,
          petBoxDetector: petBoxDetector,
          textToSpeechService: textToSpeechService,
          autoReadPreferenceStore: autoReadPreferenceStore,
          enableCamera: enableCamera,
        ),
        streakScreenBuilder: (context) =>
            PetMomentStreakScreen(streakClient: streakClient),
        chatScreenBuilder: (context) => AgentChatScreen(
          client: client,
          streakClient: streakClient,
          visualLlmClient: visualLlmClient,
          textToSpeechService: textToSpeechService,
          autoReadPreferenceStore: autoReadPreferenceStore,
        ),
      ),
    );
  }
}
