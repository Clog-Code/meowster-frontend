import 'package:flutter/material.dart';

import '../data/services/agent_stream_client.dart';
import '../data/services/pet_streak_client.dart';
import '../data/services/visual_llm_client.dart';
import 'pet_agent_app.dart';

void bootstrap() {
  const mockPetStreaks = bool.fromEnvironment('MOCK_PET_STREAKS');
  runApp(
    PetAgentApp(
      client: AgentApiClient.fromEnvironment(),
      streakClient: mockPetStreaks
          ? const DemoPetStreakClient()
          : AgentPetStreakClient.fromEnvironment(),
      visualLlmClient: VisualLlmApiClient.fromEnvironment(),
    ),
  );
}
