# Glossary

## Agent Activity Panel

The collapsible area above an assistant answer that summarizes tool calls. It expands automatically while a tool is running and collapses after completion.

## Tool Timeline Step

A single tool call displayed inside the agent activity panel. It shows the tool name, running or done status, a compact summary, and optional suggestion chips.

## Suggestion Chip

A compact chip for concrete recommendations such as clinics, pet shops, providers, or care resources extracted from tool result JSON.

## Recommendation Card

A richer replacement for suggestion chips when store/clinic/place-oriented tool results contain a recommendation. It shows the place name, brief metadata, and actions such as "Shop details" and "Book now". These cards render with the assistant output, not inside the agent activity timeline.

## HITL Card

Human-in-the-loop card rendered from `STATE_SNAPSHOT` events. It can show todos or approval actions and can be dismissed when the user is done with it.
Empty todo snapshots are hidden. Todo cards show three items by default and can expand when more steps exist.

## Thread History

The list of previous chat sessions. The Flutter UI has a drawer placeholder, but the backend still needs public APIs for listing threads and loading messages.

## Local End Chat

The current MVP action that clears active HITL cards and marks streaming as stopped in the UI. It does not yet persist thread completion to the backend.

## Pet Moment Card

The user-facing card shown after capture or gallery upload. It displays a media thumbnail placeholder plus a short pet summary, while hiding the raw perception JSON from the chat transcript.

## Mock Pet Profile

Temporary frontend profile data sent with perception payloads. It mirrors the backend `pet_profiles` table shape and should be replaced by persisted user pet profiles later.

## Location Consent Card

The card shown only when the agent needs location for nearby recommendations. "Allow once" triggers the native mobile permission flow, reads the current device position, and saves exact coordinates for the user's next typed reply.
