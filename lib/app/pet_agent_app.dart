import 'package:flutter/material.dart';

import '../data/services/agent_stream_client.dart';
import '../ui/core/pet_theme.dart';
import '../ui/features/capture/capture_screen.dart';

class PetAgentApp extends StatelessWidget {
  const PetAgentApp({
    required this.client,
    this.enableCamera = true,
    super.key,
  });

  final AgentStreamClient client;
  final bool enableCamera;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pet Agent',
      debugShowCheckedModeBanner: false,
      theme: PetTheme.dark(),
      home: CaptureScreen(client: client, enableCamera: enableCamera),
    );
  }
}
