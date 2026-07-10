# ADR-001: Agent Chat UI and History API Contract

## Status

Accepted for the Flutter MVP.

## Context

The pet agent chat receives AG-UI stream events from the backend. The previous UI rendered each tool result directly, which was useful for debugging but exposed raw JSON to the pet owner. The team also wants a menu entry for previous chats, but the backend currently persists threads and messages without public list/detail routes for the Flutter app.

## Decision

The chat screen will render agent work as a collapsible activity panel:

- While a tool is running, the panel expands and shows a compact timeline.
- After all tools complete, the panel collapses to a single "Agent steps complete" row.
- Expanding the panel shows each tool as a timeline step with a short summary.
- Tool result JSON is summarized into human-readable text instead of displayed raw.
- Candidate places, providers, clinics, shops, or similar suggestions render as recommendation cards in the assistant output area, not inside the agent activity timeline. The timeline remains process-only. Recommendation cards are gated to store/clinic/place-oriented tools or result containers, so profile-style tool results do not show "Shop details" or "Book now".
- Recommendation cards expose "Shop details" and "Book now" affordances. For the MVP, "Shop details" opens an in-app details sheet with a Google search URL; a later pass can replace this with direct `url_launcher` navigation.
- HITL checklist cards are hidden when the snapshot has no todos. When there are more than three todos, the card shows the first three and offers an expand control.

Captured media is displayed as a user-facing pet moment card instead of raw perception JSON. The backend still receives the full `/perception` payload, including a mock `pet_profile` object aligned with the backend `pet_profiles` table:

- `pet_id`
- `name`
- `species`
- `breed`
- `weight_kg`
- `life_stage`
- `known_conditions`
- `delivery_address`
- `preferred_clinic`
- `preferred_food_brand`

When the agent asks for user location, the frontend displays an explicit permission-style card. Accepting triggers the native mobile location permission flow through `geolocator`, reads the current device position, and temporarily saves it. The location is sent with the user's next typed reply, which lets the user answer follow-up questions such as weight and known conditions in the same request. In the backend's current `ag_ui_protocol` version, context entries must use the shape `{ "description": "...", "value": "..." }`, where `value` is a string. JSON-like context must be serialized before sending; arbitrary keys at the context item root or object values will fail backend `RunAgentInput` validation. The normal user message suffix is still needed because `backend/main.py` validates `body.context`, but `agent/core/runner.py` currently passes only `body.messages` into the LangGraph agent.

The top-right chat action is now a menu button. It opens a drawer with:

- the current thread id,
- a capture entry point,
- an "End current chat" action that clears active HITL cards locally,
- placeholder copy for previous chats until backend history APIs are available.

## Backend API Gap

The backend already stores threads and messages, but Flutter still needs public mobile-safe read APIs. Suggested first contract:

```http
GET /threads
```

```json
{
  "threads": [
    {
      "thread_id": "thread_abc",
      "title": "Mochi limping check",
      "created_at": "2026-07-09T10:30:00Z",
      "updated_at": "2026-07-09T10:35:00Z",
      "last_message_preview": "The closest clinic is open now.",
      "status": "active"
    }
  ]
}
```

```http
GET /threads/{thread_id}/messages
```

```json
{
  "thread_id": "thread_abc",
  "messages": [
    {
      "id": "msg_1",
      "role": "user",
      "content": "My pet is limping",
      "created_at": "2026-07-09T10:31:00Z"
    }
  ]
}
```

Useful follow-up endpoint:

```http
PATCH /threads/{thread_id}
```

```json
{
  "status": "completed",
  "title": "Mochi limping check"
}
```

## Consequences

The MVP keeps the working AG-UI integration while making the chat feel less like a debug console. The drawer can be wired to real thread history later without redesigning the navigation. The "End current chat" action is local-only until the backend supports thread status updates.
