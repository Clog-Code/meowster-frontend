### mingjia's Command

```bash
flutter run \
  --dart-define=AGENT_BASE_URL=http://192.168.0.101:8000 \
  --dart-define=VISUAL_MODEL_BASE_URL=http://192.168.0.101:8001 \
  --dart-define=TTS_BASE_URL=http://192.168.0.101:8002 \
  --dart-define=MOCK_PET_STREAKS=true
```

# AMD Pet Frontend

Mobile Flutter frontend for the Pet Mental & Physical Health Agent. The app is built for the AMD Developer Hackathon ACT II project and focuses on capturing pet moments, especially cats for the MVP, then handing structured perception events to an agentic backend over AG-UI streams.

The app opens into a camera-first capture experience, then moves into an agent chat where users can text, upload pet media, view tool execution, and approve agent actions such as finding clinics or care next steps.

## Features

- Mobile-first Flutter app for iOS and Android.
- Immersive capture screen with camera, gallery upload, demo capture fallback, 10-second recording cap, and pet health overlay labels.
- Agentic chat screen with an expanding text composer, gallery entry point, hold-to-talk native dictation, live transcript waveform, and Kokoro response playback.
- AG-UI-compatible streaming client for backend `POST /agent` and `POST /perception`.
- Live rendering for AG-UI events:
  - `TEXT_MESSAGE_START`, `TEXT_MESSAGE_CONTENT`, `TEXT_MESSAGE_END`
  - `TOOL_CALL_START`, `TOOL_CALL_ARGS`, `TOOL_CALL_END`, `TOOL_CALL_RESULT`
  - `STATE_SNAPSHOT`
  - `RUN_ERROR`
- Collapsible agent activity timeline for tool work such as clinic search or knowledge lookup.
- Suggestion chips for clinic, shop, provider, or care recommendations returned by tools.
- Human-in-the-loop cards for todos and approval flows, with a local dismiss action.
- Chat menu drawer with the current thread and a placeholder for future backend thread history.
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
source venv/bin/activate
uv sync
uv run uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
```

Open `http://localhost:8000/healthz` on the backend machine to confirm it is alive.

Start the visual model emotion service from the sibling `amd-pet-visual-cnn`
project on a separate port:

```bash
cd ../amd-pet-visual-cnn
uv sync
source venv/bin/activate
uv run uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload
```

Start the Kokoro TTS service from the sibling `amd-pet-tts` project:

```bash
cd ../amd-pet-tts
uv sync
source venv/bin/activate
uv run uvicorn main:app --reload --host 0.0.0.0 --port 8002
```


Then pass both backend URLs when running the app:

```bash
flutter run \
  --dart-define=AGENT_BASE_URL=http://localhost:8000 \
  --dart-define=VISUAL_MODEL_BASE_URL=http://localhost:8001 \
  --dart-define=TTS_BASE_URL=http://localhost:8002
```

---

Run the Flutter app on the iOS simulator:

```bash
flutter run \
  --dart-define=AGENT_BASE_URL=http://localhost:8000 \
  --dart-define=TTS_BASE_URL=http://localhost:8002
```

To demo the pet moment streak calendar before the backend endpoint is ready,
run with mock streak history:

```bash
flutter run \
  --dart-define=AGENT_BASE_URL=http://localhost:8000 \
  --dart-define=VISUAL_MODEL_BASE_URL=http://localhost:8001 \
  --dart-define=TTS_BASE_URL=http://localhost:8002 \
  --dart-define=MOCK_PET_STREAKS=true
```

Run on Android emulator:

```bash
flutter run \
  --dart-define=AGENT_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=VISUAL_MODEL_BASE_URL=http://10.0.2.2:8001 \
  --dart-define=TTS_BASE_URL=http://10.0.2.2:8002
```

Run on a physical Android phone or iPhone on the same Wi-Fi as your backend machine:

```bash
flutter run \
  --dart-define=AGENT_BASE_URL=http://<YOUR_COMPUTER_LAN_IP>:8000 \
  --dart-define=TTS_BASE_URL=http://<YOUR_COMPUTER_LAN_IP>:8002
```

Example:

```bash
flutter run \
  --dart-define=AGENT_BASE_URL=http://192.168.1.42:8000 \
  --dart-define=TTS_BASE_URL=http://192.168.1.42:8002
```

---

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

Gallery image and recorded video emotion checks read the visual cnn backend URL
from:

```text
VISUAL_MODEL_BASE_URL
```

Default:

```text
http://localhost:8001
```

Agent response playback reads the Kokoro backend URL from:

```text
TTS_BASE_URL
```

Default:

```text
http://localhost:8002
```

The service must expose `GET /tts?text=...` and return `audio/wav`. Auto-read
starts enabled; muting it in the response action row persists across app
restarts. Hold-to-talk uses the device speech recognizer and keeps the
transcript as an editable draft when released.

The visual model service is expected to expose:

- `POST /predict` for image uploads.
- `POST /predict_video` for video uploads sampled by the backend.

Use the right host for the runtime:

| Runtime                | Backend URL when backend runs on your computer |
| ---------------------- | ---------------------------------------------- |
| iOS simulator          | `http://localhost:8000`                      |
| Android emulator       | `http://10.0.2.2:8000`                       |
| Physical iPhone        | `http://<YOUR_COMPUTER_LAN_IP>:8000`         |
| Physical Android phone | `http://<YOUR_COMPUTER_LAN_IP>:8000`         |

Why they differ:

- `localhost` means "this current device."
- The iOS simulator shares the Mac's loopback network, so `localhost:8000` reaches your Mac.
- The Android emulator runs behind its own virtual network, so Android reserves `10.0.2.2` as the host-machine alias.
- A physical phone's `localhost` is the phone itself, not your laptop. Use your laptop's LAN IP and start the backend with `--host 0.0.0.0`.
- Apply the same host rule to ports `8001` and `8002` for the visual and TTS services.

If the backend sets `PERCEPTION_INGEST_TOKEN` in `.env`, pass the same value to Flutter:

```bash
flutter run \
  --dart-define=AGENT_BASE_URL=http://<YOUR_BACKEND_HOST>:8000 \
  --dart-define=AGENT_PERCEPTION_TOKEN=<TOKEN>
```

Expected backend endpoints:

- `POST /agent` for normal chat runs.
- `POST /perception` for pet media/perception events.
- `GET /pet-moments/streaks?pet_id=pet-01` for current streak and monthly
  pet moment history.

`/agent` and `/perception` are expected to return AG-UI-style Server-Sent
Events with `data:` JSON blocks. `/pet-moments/streaks` returns normal JSON:

```json
{
  "current_streak": 4,
  "longest_streak": 9,
  "month_start": "2026-07-01",
  "days": [
    {
      "date": "2026-07-09",
      "capture_count": 1,
      "dominant_emotion": "curious",
      "species": "cat"
    }
  ]
}
```

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
      speech_to_text_service.dart   # Native dictation and continuous segment merging
      text_to_speech_service.dart   # Kokoro playback and persisted auto-read preference
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
        chat_composer.dart          # Expanding text and hold-to-talk composer

android/                            # Android mobile target
ios/                                # iOS mobile target
test/
  widget_test.dart                  # Parser and UI behavior tests
  data/services/                    # STT transcript and Kokoro helper unit tests
docs/
  adr/
    ADR-001-agent-chat-ui-and-history-api.md
  glossary.md
DESIGN.md                           # Visual and interaction design notes
AGENT.md                            # Product/system spec for the agent frontend
```

## Current MVP Notes

- Gallery images and recorded videos can be analyzed by the visual CNN service; if it is unavailable, capture falls back to review-mode perception.
- Voice input uses device-native dictation; it is not backend audio streaming and may inherit platform pause limits.
- Previous chat history is represented in the UI, but the backend still needs thread list/message read APIs before it can be connected.
- The app currently targets mobile only; desktop and web platform folders were removed to keep the project focused.
- Camera/gallery permissions are configured for Android and iOS.

## Team Handoff

Backend integration should follow the behavior of the existing AG-UI test harness:

- Send full `RunAgentInput` payloads to `/agent`.
- Send pet perception payloads to `/perception`.
- Always include `species`, defaulting to `cat` for the MVP.
- Treat malformed SSE events as ignorable.
- If a stream breaks before completion, remove incomplete assistant output and show a retry prompt.
