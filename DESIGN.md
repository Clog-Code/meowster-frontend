# Pet Agent Frontend Design

## Product Feel

The app is a photo-first pet health companion. It should open directly into the pet moment, feel immediate like a story camera, and then become clear and trustworthy when the AI agent starts working.

Copy stays pet-neutral. Cats are the MVP default, but screens should say "Pet" unless a backend payload supplies a species label.

## Visual System

- Backgrounds: near black photo surfaces, `#0E1116`, with real camera/video/image content as the main visual.
- Text: warm ivory `#F6F0E8` for primary text and muted blue gray `#B8C0C9` for secondary text.
- Accents: aqua `#65D6D0` for primary actions, coral `#FF8A66` for urgency, sage `#A5C68A` for completed work, warning yellow `#FFC857` for approvals.
- Corners: 8px for cards, chips, buttons, sheets, and framed controls.
- Type: system sans for app UI. Camera overlay headlines use a Georgia-style serif to echo the reference image.
- Letter spacing: 0. Use weight and casing instead of tracked-out text.

## Capture Page

- Full-screen camera or media preview with a dark vertical gradient for legibility.
- Overlay content sits near the lower third: small status chips, serif title, divider, short supporting copy.
- Capture controls remain icon-driven: gallery, record/stop, and chat.
- Recording is capped at 10 seconds.
- Preview state shows species/emotion/health flags as overlay labels and exposes Retake and Ask Agent.

## Chat Page

- Main surface is dark and compact, with a centered max-width layout on large windows.
- Input bar has camera/gallery, voice, text field, and send controls.
- Voice opens a pending live-call sheet until STT/TTS endpoints are ready.
- Tool execution is rendered as dark timeline chips attached to the assistant message.
- Final answers render as markdown-ready assistant bubbles.
- HITL snapshots render as elevated approval cards with Approve, Modify, and Cancel.

## AG-UI States

- `TEXT_MESSAGE_START`, `TEXT_MESSAGE_CONTENT`, `TEXT_MESSAGE_END`: stream into one assistant bubble.
- `TOOL_CALL_START`: append a running timeline chip.
- `TOOL_CALL_RESULT`: mark the latest running chip as complete and show result text.
- `STATE_SNAPSHOT`: render todos or action approval cards inline.
- `RUN_ERROR`: show an error system bubble.
- Broken streams before completion remove the incomplete assistant bubble and show the network snackbar.
