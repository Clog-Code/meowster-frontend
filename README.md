# AMD Pet Frontend

Mobile Flutter frontend for the Pet Mental & Physical Health Agent. Built for the AMD Developer Hackathon ACT II project. The app opens into an isometric pet room with animated cat sprites, then lets users capture pet moments (photo/video), analyze emotions via a visual LLM, chat with an AI pet health agent over AG-UI SSE streams, and track daily streaks on a calendar.

## Features

- **Isometric Pet Room Home** — A 2.5D cozy bedroom that changes with time of day (morning, noon, sunset, night). Animated cat sprites walk, sit, sleep, and lick with 8 action states. Pinch-to-zoom/pan. Tap a pet to reveal a glassmorphism stat card (species, mood, breed, weight, conditions, clinic, food brand).
- **Immersive Capture Screen** — Full-screen camera with photo tap, 10-second video recording (long-press with zoom via vertical drag), gallery upload (photo or video), tap-to-focus, zoom multipliers (.5x–5x), and demo capture fallback. Preview replay shows ML emotion tags (species, emotion, confidence). Concurrent visual LLM prediction and Google Lens-style upload.
- **Pet Moment Streak Calendar** — Monthly calendar with day cells colored by emotion (healthy/warning/unhealthy), weekly bar chart, usage ring, and a moment reel with photo/video previews. Streak metrics (current, longest, monthly count) from the backend or mock data.
- **Agentic Chat** — SSE-streaming AI conversation with markdown rendering, tool call timeline (collapsible, with step-by-step status), recommendation cards (clinics, shops), HITL approval cards (checklist + send/cancel), and location permission prompts.
- **Chat Composer** — Expandable text field (1–6 lines), smart mic button (tap-to-confirm vs hold-to-talk), gallery attachment upload, send/stop. Voice dictation with live waveform and editable transcript on release.
- **Add Pet Form** — Responsive dialog with name, species dropdown (Cat/Dog/Bird/Other + custom), breed, life stage (Baby/Young/Adult/Senior), weight (decimal, kg suffix), photo picker, and optional care details (conditions, clinic, food brand, delivery address). Can skip and use "Chat with Agent" instead.
- **Owner Profile** — Editable name, phone, and address dialog.
- **AG-UI Streaming** — Full SSE event support: `TEXT_MESSAGE_START/CONTENT/END`, `TOOL_CALL_START/ARGS/END/RESULT`, `STATE_SNAPSHOT`, `RUN_ERROR`.
- **Agent Auto-Read** — Completed assistant answers read aloud via Kokoro TTS. Mute persists across restarts via `SharedPreferences`.
- **Pet-Neutral Frontend** — `species` key included in every perception payload. All UI uses "Pet" unless the backend supplies a species label.
- **Local Moment Storage** — Captured media copied to app documents directory with a JSON index for offline access.
- **Conditional Dart Bootstrap** — `dart lib/main.dart` prints instructions instead of crashing.

## Quickstart

Install Flutter, then fetch dependencies:

```bash
flutter pub get
```

If you are running the app on a physical Android device, forward the backend
ports from the device to the host machine:

```bash
adb reverse tcp:8000 tcp:8000
adb reverse tcp:8001 tcp:8001
adb reverse tcp:8002 tcp:8002
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
- `POST /upload` for multipart file uploads (visual search).
- `GET /pet-profiles` ─ list registered pets.
- `GET /pet-profile/{id}` ─ single pet profile.
- `POST /pet-profile` ─ create new pet profile.
- `GET /pet-moments/streaks?pet_id=pet-01` ─ streak summary and monthly history.
- `GET /threads` ─ conversation thread list.
- `GET /threads/{id}/messages` ─ thread message history.

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
    bootstrap_flutter.dart          # Flutter bootstrap (env vars, DI wiring)
    bootstrap_stub.dart             # Standalone Dart VM stub
    pet_agent_app.dart              # Root MaterialApp with theme
  data/
    services/
      agent_stream_client.dart      # AG-UI SSE parser, chat models, agent API client
      local_moment_storage.dart     # Persists captured media to app documents
      location_service.dart         # GPS location via geolocator
      pet_streak_client.dart        # Streak API client (production + demo)
      speech_to_text_service.dart   # Native dictation, transcript accumulator
      text_to_speech_service.dart   # Kokoro TTS playback, auto-read prefs
      visual_llm_client.dart        # Visual emotion prediction client
  domain/
    models/
      camera_zoom_state.dart        # Zoom math + debounced request coordinator
      owner_profile.dart            # Owner name/phone/address
      pet_capture_result.dart       # Capture result, perception payload builder
      pet_streak_summary.dart       # Streak day/summary models
  ui/
    core/
      pet_theme.dart                # Dark theme, accent colors, radii
    features/
      capture/
        capture_screen.dart         # Camera/gallery/demo capture flow
        view_models/
          capture_view_model.dart           # Capture UI state management
        views/
          camera_preview_cover.dart         # Camera preview sizing
      chat/
        agent_chat_screen.dart      # Agent chat, timeline, HITL cards, recommendations
        chat_composer.dart          # Text field, smart mic, voice panel, attachment
      home/
        models/
          pet_room_state.dart       # Room assets, pet state, standby actions
        view_models/
          isometric_home_view_model.dart    # Home logic, pet animations, API fetches
        views/
          isometric_home_page.dart          # Isometric room, pet sprites, stat card, add pet form
        widgets/
          owner_profile_content.dart        # Owner profile edit dialog

android/                          # Android mobile target
ios/                              # iOS mobile target
test/
  widget_test.dart                # Full integration tests (capture, chat, streaks)
  data/services/
    speech_to_text_service_test.dart       # STT transcript accumulator tests
    text_to_speech_service_test.dart       # TTS helper unit tests
  domain/models/
    camera_zoom_state_test.dart            # Zoom math tests
  ui/features/
    capture/
      camera_preview_cover_test.dart       # Preview sizing tests
      capture_view_model_test.dart         # Capture VM state tests
    chat/
      chat_composer_test.dart              # Composer widget tests
    home/
      isometric_home_page_test.dart        # Home page, add pet form tests
      isometric_home_view_model_test.dart  # Home VM animation tests
docs/
  adr/
    ADR-001-agent-chat-ui-and-history-api.md
  glossary.md
DESIGN.md                         # Visual and interaction design notes
AGENT.md                          # Product/system spec
```

## Current MVP Notes

- Gallery images and recorded videos can be analyzed by the visual CNN service; if it is unavailable, capture falls back to review-mode perception.
- Voice input uses device-native dictation; it is not backend audio streaming and may inherit platform pause limits.
- Previous chat history is represented in the UI drawer, but the backend thread list/message read APIs need to be connected.
- The app currently targets mobile only; desktop and web platform folders were removed.
- Camera/gallery permissions are configured for Android and iOS.
- Pet streak calendar can operate with mock data via `--dart-define=MOCK_PET_STREAKS=true`.
- Pet profiles can be created via the Add Pet dialog or the "Chat with Agent" flow.
- Demo captures exercise the agent without creating backend pet-moment rows or incrementing streaks.

## Team Handoff

Backend integration should follow the behavior of the existing AG-UI test harness:

- Send full `RunAgentInput` payloads to `/agent`.
- Send pet perception payloads to `/perception`.
- Always include `species`, defaulting to `cat` for the MVP.
- Treat malformed SSE events as ignorable.
- If a stream breaks before completion, remove incomplete assistant output and show a retry prompt.
