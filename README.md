# AMD Pet Frontend

Mobile Flutter frontend for the Pet Mental & Physical Health Agent. The app is built for the AMD Developer Hackathon ACT II project and focuses on capturing pet moments, especially cats for the MVP, then handing structured perception events to an agentic backend over AG-UI streams.

The app opens into a camera-first capture experience, then moves into an agent chat where users can text, upload pet media, view tool execution, and approve agent actions such as finding clinics or care next steps.

## Features

- Mobile-first Flutter app for iOS and Android.
- Immersive capture screen with camera, gallery upload, demo capture fallback, 10-second recording cap, and pet health overlay labels.
- Agentic chat screen with text input, camera/gallery entry point, and a voice-call placeholder for future STT/TTS integration.
- AG-UI-compatible streaming client for backend `POST /agent` and `POST /perception`.
- Live rendering for AG-UI events:
  - `TEXT_MESSAGE_START`, `TEXT_MESSAGE_CONTENT`, `TEXT_MESSAGE_END`
  - `TOOL_CALL_START`, `TOOL_CALL_RESULT`
  - `STATE_SNAPSHOT`
  - `RUN_ERROR`
- Tool timeline chips for agent work such as clinic search or knowledge lookup.
- Human-in-the-loop cards for todos and approval flows.
- Pet-neutral frontend model with `species` included in perception payloads.
- Conditional Dart bootstrap so accidental `dart lib/main.dart` runs show a helpful message instead of crashing.

## Quickstart

Install Flutter, then fetch dependencies:

```bash
flutter pub get
```

Start the backend agent from the sibling `amd-pet-agentic` project:

```bash
cd ../amd-pet-agentic
cp .env.example .env
uv sync
uv run uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
```

Open `http://localhost:8000/healthz` on the backend machine to confirm it is alive.

Run the Flutter app on the iOS simulator:

```bash
flutter run --dart-define=AGENT_BASE_URL=http://localhost:8000
```

Run on Android emulator:

```bash
flutter run --dart-define=AGENT_BASE_URL=http://10.0.2.2:8000
```

Run on a physical Android phone or iPhone on the same Wi-Fi as your backend machine:

```bash
flutter run --dart-define=AGENT_BASE_URL=http://<YOUR_COMPUTER_LAN_IP>:8000
```

Example:

```bash
flutter run --dart-define=AGENT_BASE_URL=http://192.168.1.42:8000
```

Run checks:

```bash
flutter analyze
flutter test
```

## VS Code

Use the checked-in Flutter launch profile:

```text
Run and Debug -> Flutter: Pet Agent
```

Do not use Code Runner's plain Dart command for the app. Flutter plugins such as camera and video playback need the Flutter toolchain. If `dart lib/main.dart` is run accidentally, the project now prints a short instruction instead of trying to launch the app.

## Backend Configuration

The app reads the agent backend URL from:

```text
AGENT_BASE_URL
```

Default:

```text
http://localhost:8000
```

Use the right host for the runtime:

| Runtime | Backend URL when backend runs on your computer |
| --- | --- |
| iOS simulator | `http://localhost:8000` |
| Android emulator | `http://10.0.2.2:8000` |
| Physical iPhone | `http://<YOUR_COMPUTER_LAN_IP>:8000` |
| Physical Android phone | `http://<YOUR_COMPUTER_LAN_IP>:8000` |

Why they differ:

- `localhost` means "this current device."
- The iOS simulator shares the Mac's loopback network, so `localhost:8000` reaches your Mac.
- The Android emulator runs behind its own virtual network, so Android reserves `10.0.2.2` as the host-machine alias.
- A physical phone's `localhost` is the phone itself, not your laptop. Use your laptop's LAN IP and start the backend with `--host 0.0.0.0`.

If the backend sets `PERCEPTION_INGEST_TOKEN` in `.env`, pass the same value to Flutter:

```bash
flutter run \
  --dart-define=AGENT_BASE_URL=http://<YOUR_BACKEND_HOST>:8000 \
  --dart-define=AGENT_PERCEPTION_TOKEN=<TOKEN>
```

Expected backend endpoints:

- `POST /agent` for normal chat runs.
- `POST /perception` for pet media/perception events.

Both endpoints are expected to return AG-UI-style Server-Sent Events with `data:` JSON blocks.

## Folder Structure

```text
lib/
  main.dart                         # Entrypoint with conditional bootstrap
  app/
    bootstrap_flutter.dart          # Real Flutter app bootstrap
    bootstrap_stub.dart             # Friendly plain-Dart fallback
    pet_agent_app.dart              # MaterialApp setup
  data/
    services/
      agent_stream_client.dart      # AG-UI SSE parser and HTTP streaming client
  domain/
    models/
      pet_capture_result.dart       # Capture/perception domain model
  ui/
    core/
      pet_theme.dart                # Shared colors and app theme
    features/
      capture/
        capture_screen.dart         # Camera/gallery/demo capture flow
      chat/
        agent_chat_screen.dart      # Agent chat, timeline, HITL cards

android/                            # Android mobile target
ios/                                # iOS mobile target
test/
  widget_test.dart                  # Parser and UI behavior tests
DESIGN.md                           # Visual and interaction design notes
AGENT.md                            # Product/system spec for the agent frontend
```

## Current MVP Notes

- The media analysis endpoint is not ready yet, so captured media produces simulated perception JSON and streams it through `/perception`.
- Voice UI is intentionally present but not connected to microphone streaming.
- The app currently targets mobile only; desktop and web platform folders were removed to keep the project focused.
- Camera/gallery permissions are configured for Android and iOS.

## Team Handoff

Backend integration should follow the behavior of the existing AG-UI test harness:

- Send full `RunAgentInput` payloads to `/agent`.
- Send pet perception payloads to `/perception`.
- Always include `species`, defaulting to `cat` for the MVP.
- Treat malformed SSE events as ignorable.
- If a stream breaks before completion, remove incomplete assistant output and show a retry prompt.
