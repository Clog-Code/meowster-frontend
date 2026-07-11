# Pet Mental & Physical Health Agent - System Spec (MVP)

## 1. Architecture Overview
- **Frontend:** Flutter (Mobile App). Local-first mindset for media, API-driven for intelligence.
- **Agent & Backend:** LangChain + Fireworks AI API (Qwen3.7-Plus) + LangSmith handled by teammate.
- **Database:** SQLite (Backend managed, UI will call API to DB).
- **STT & TTS:** Fireworks AI API, will be integrated.
- **ML Models:** Teammate's vision/audio model for pet emotion and health analysis, pending for integration.
- **Communication:** REST POST (Input) & AG-UI SSE Stream (Output).

## 2. Requirements, Future-Proofing & Development Rules
The system is built as a generic "Pet Agent". Species-specific logic is entirely decoupled from the Flutter frontend UI.
- **AI Coding Rules (STRICT MANDATE):** All frontend development MUST strictly utilize the provided local `.agents` Flutter/Dart skills (e.g., `flutter-apply-architecture-best-practices`, `flutter-build-responsive-layout`, `dart-*`). Do NOT generate generic or boilerplate Flutter code. The AI must route its logic through these skills to ensure high-quality, idiomatic, and testable architecture.
- **API Contract:** All payloads must include the `species` key (e.g., `"species": "cat"`).
- **UI Theming:** Flutter UI should remain neutral (using "Pet" instead of "Cat"). Asset rendering (placeholders, icons) should dynamically resolve based on the current `species` state.
- **Overlay Agnosticism:** Flutter blindly renders the `emotion` and `health_flags` strings provided by the ML backend, making it inherently cross-species (e.g., rendering "purring" for cats or "panting" for dogs seamlessly).

## 3. Multimodal UI Flows (Flutter)
**A. The Home Page (2.5D Isometric Pet Room)**
- **Concept:** A "Focus Friend" style passive UI where the pet resides.
- **Layout (Stack-based):**
  - _Base Layer_: A static isometric room background. The image changes dynamically based on the user's current local time (Morning, Noon, Sunset, Night).
  - _Pet Layer_: A 2.5D Positioned element playing a transparent cat animation GIF.
- **Interaction:** Tapping the pet triggers a Glassmorphism (blur-backed) "Pet Stat Card" showing the pet's name, species, and current emotion.

**B. The Snap & Analyze View**
1. **Immersive Camera UI:** Based on the reference UI design from SnapChat and SetLog, the initial page is an immersive, full-screen camera viewfinder (similar to a "Snap" or "Story" interface) with minimal UI clutter over the live feed.
2. **Navigation to Home:** A subtle, floating "Home" or "Pet Room" button exists on this screen to navigate the user to the Isometric Home Page.
3. **Capture Mechanism:** User's camera is auto-opened to take video of the pet (Max 10 seconds). Users could also upload existing pet videos via a gallery action.
4. **Processing:** After user finishes capturing, it will replay the video; while Flutter sends media to ML Endpoint (Teammate's vision/audio model).
5. **Overlay Rendering:** ML returns JSON (e.g., `{"emotion": "distress", "species": "cat"}`). Flutter renders a UI `Stack` with the replay video and overlays generic tags based on the JSON (e.g., "British Shorthair, Distress").
6. **Transition:** User clicks an "Ask Agent" or "Send" button -> Transitions to the Agentic Chat View, passing the structured JSON payload.

**C. The Multimodal Input Bar (Chat View)**
- Rounded text field taking up most of the width.
- 📷 Camera/Gallery Icon (Triggers Snap View / Media Upload).
- 🎙️ Voice Icon (Triggers STT/Audio streaming).

## 4. AG-UI Protocol & The Agentic Message Lifecycle
The Flutter app must parse the SSE stream (`/agent` or `/perception`) and render the state machine visually based on the backend events.

**Phase A & B: Thinking & Tool Execution**
- Triggered by: `TOOL_CALL_START` (e.g., `{"toolCallName": "search_clinics"}`)
- UI Render: Show dark UI chips or terminal-style blocks. 
  - *Example:* `[spinner] 📍 Searching Google Maps for vet clinics...`
- Triggered by: `TOOL_CALL_RESULT`
  - UI Render: Change spinner to checkmark. `[check] 📞 Found 3 clinics.`

**Phase C: Final Output**
- Triggered by: `TEXT_MESSAGE_START` / `_CONTENT` / `_END`
- UI Render: Standard fade in effect rendering markdown.

**Phase D: Human-in-the-Loop (HITL) & Generative UI**
- Triggered by: `STATE_SNAPSHOT`
- UI Render: When the agent needs approval or displays structured data, render an elevated, interactive card within the chat stream.
  - *Example 1 (Todos):* A checklist rendered from `snapshot.todos`.
  - *Example 2 (Action Approval):* A card with Approve or Cancel buttons that triggers a new POST request back to the agent with the user's decision.

## 5. Error Handling & Edge Cases
- **SSE Disconnect:** If stream breaks before `TEXT_MESSAGE_END`, catch `SocketException` or stream closure, completely remove the current incomplete assistant message bubble from the UI state, and show a `SnackBar`: "Network unstable. Please try again."

## 6. API Endpoints Contract
**A. `POST /agent`** (Standard Chat)
- **Payload:** `{ threadId: string, messages: array, user_location: { lat: float, lng: float } }`
- **Response:** AG-UI SSE Stream.

**B. `POST /perception`** (Multimodal Analysis Trigger)
- **Payload:**
  {
    "pet_id": "string",
    "species": "cat",
    "emotion": "distress",
    "health_flags": ["limping"],
    "thread_id": "string",
    "user_location": { "lat": 3.1390, "lng": 101.6869 } 
  }
- **Response:** AG-UI SSE Stream.