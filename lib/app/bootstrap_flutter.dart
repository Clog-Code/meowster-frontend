import 'package:flutter/material.dart';

import '../data/services/agent_stream_client.dart';
import 'pet_agent_app.dart';

void bootstrap() {
  runApp(PetAgentApp(client: AgentApiClient.fromEnvironment()));
}
