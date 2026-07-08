# Pet Mental & Physical Health Agent - System Spec (MVP)

## 1. Architecture Overview
- **Frontend:** Flutter (Mobile App). Local-first mindset for media, API-driven for intelligence.
- **Agent & Backend:** LangChain + Fireworks AI API (Qwen3.7-Plus) + LangSmith handled by teammate.
- **Database:** SQLite (Backend managed, UI will call API to DB).
- **STT & TTS:** Fireworks AI API, will be integrated.
- **ML Models:** Teammate's vision/audio model for pet emotion and health analysis, pending for integration.
- **Communication:** REST POST (Input) & AG-UI SSE Stream (Output).

## 2. Requirements & Future-Proofing (Cat -> Dog)
The system is built as a generic "Pet Agent". Species-specific logic is entirely decoupled from the Flutter frontend UI.
- **AI Coding Rules (STRICT MANDATE):** All payloads must include the `species` key (e.g., `"species": "cat"`).
- **UI Theming:** Flutter UI should remain neutral (using "Pet" instead of "Cat"). Asset rendering (placeholders, icons) should dynamically resolve based on the current species state.
- **Overlay Agnosticism:** Flutter blindly renders the emotion and health_flags strings provided by the ML backend, making it inherently cross-species (e.g., rendering "purring" for cats or "panting" for dogs seamlessly).

## 3. Multimodal UI Flows (Flutter)
**A. The Snap & Analyze View**
1. **Immersive Camera UI:** Based on the reference UI design, the initial page is an immersive, full-screen camera viewfinder (similar to a "Snap" or "Story" interface) with minimal UI clutter over the live feed.
2. **Capturing Mechanism:** User's camera is auto-opened to take video of the pet (Max 10 seconds).
3. **Processing:** After user finishes capturing, it will replay the video; while Flutter sends media to ML Endpoint (Teammate's vision/audio model).
4. **Overlay Rendering:** ML returns JSON (e.g., `{"emotion": "distress", "species": "cat"}`). Flutter renders a UI `Stack` with the replay video and overlays generic tags based on the JSON (e.g., "British Shorthair, Distress").
5. **Transition:** User clicks an "Ask Agent" or "Send" button -> Transitions to the Agentic Chat View, passing the structured JSON payload.

**B. The Multimodal Input Bar (Chat View)**
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
- UI Render: Standard chat bubble with typewriter effect rendering markdown.

**Phase D: Human-in-the-Loop (HITL) & Generative UI**
- Triggered by: `STATE_SNAPSHOT`
- UI Render: When the agent needs approval or displays structured data, render an elevated, interactive card within the chat stream.
  - *Example 1 (Todos):* A checklist rendered from `snapshot.todos`.
  - *Example 2 (Action Approval):* A card with [ Approve ] or [ Cancel ] buttons that triggers a new POST request back to the agent with the user's decision.

## 5. Error Handling & Edge Cases
- **SSE Disconnect:** If stream breaks before `TEXT_MESSAGE_END`, catch `SocketException` or stream closure, completely remove the current incomplete assistant message bubble from the UI state, and show a `SnackBar`: "Network unstable. Please try again."

## 6. API Endpoints Contract
**A. `POST /agent`** (Standard Chat)
- **Payload:** `{ threadId: string, messages: array }`
- **Response:** AG-UI SSE Stream.

**B. `POST /perception`** (Multimodal Analysis Trigger)
- **Payload:**
  {
    "pet_id": "string",
    "species": "cat",
    "emotion": "distress",
    "health_flags": ["limping"],
    "thread_id": "string"
  }
- **Response:** AG-UI SSE Stream.