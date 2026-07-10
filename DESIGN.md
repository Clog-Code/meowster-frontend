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
- The composer is split into a fixed push-to-talk control and a flexible text surface. The text field begins at one line and expands upward to six lines.
- Holding the microphone requests native speech permission and replaces the text surface with a reactive waveform and live transcript. Releasing returns the transcript as an editable draft; it never auto-sends.
- The native recognizer restarts short platform sessions while the control remains held, accepting that some Android devices may introduce a brief gap or system beep.
- Gallery and send/stop controls stay inside the typing surface. Starting push-to-talk stops response audio first.
- User messages render as compact right-aligned bubbles.
- Assistant responses render as full-width answer blocks without a surrounding bubble, so text and structured cards read like page content.
- Tool execution is rendered as collapsed process metadata inside the assistant answer block.
- Recommendation, location, pet moment, and system error surfaces remain 8px cards.
- HITL snapshots live behind the app-bar checklist icon and render as elevated approval/checklist cards in a sheet.
- Checklist sheets are draggable and scrollable so expanded task lists never overflow.
- Completed assistant answers auto-read through Kokoro unless the persistent app-wide preference is muted. Copy and mute/read-aloud actions sit together below the answer.
- Location permission cards appear only below completed assistant output, never while the answer is still streaming.

## AG-UI States

- `TEXT_MESSAGE_START`, `TEXT_MESSAGE_CONTENT`, `TEXT_MESSAGE_END`: stream into one assistant answer block.
- `TOOL_CALL_START`: append a running timeline chip.
- `TOOL_CALL_RESULT`: mark the latest running chip as complete and show result text.
- `STATE_SNAPSHOT`: update the app-bar checklist sheet with todos or action approvals.
- `RUN_ERROR`: show an error system bubble.
- Broken streams before completion remove the incomplete assistant bubble and show the network snackbar.
