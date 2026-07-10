import 'package:flutter/material.dart';

import '../../core/pet_theme.dart';

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    required this.controller,
    required this.isSending,
    required this.isListening,
    required this.soundLevel,
    required this.onGallery,
    required this.onPushToTalkStart,
    required this.onPushToTalkEnd,
    required this.onSend,
    required this.onStop,
    super.key,
  });

  final TextEditingController controller;
  final bool isSending;
  final bool isListening;
  final double soundLevel;
  final VoidCallback onGallery;
  final VoidCallback onPushToTalkStart;
  final VoidCallback onPushToTalkEnd;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _PushToTalkButton(
              enabled: !isSending,
              listening: isListening,
              onStart: onPushToTalkStart,
              onEnd: onPushToTalkEnd,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: isListening
                    ? _ListeningComposer(
                        key: const ValueKey('listening-composer'),
                        transcript: controller.text,
                        soundLevel: soundLevel,
                      )
                    : _TypingComposer(
                        key: const ValueKey('typing-composer'),
                        controller: controller,
                        isSending: isSending,
                        compact: constraints.maxWidth < 360,
                        onGallery: onGallery,
                        onSend: onSend,
                        onStop: onStop,
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PushToTalkButton extends StatelessWidget {
  const _PushToTalkButton({
    required this.enabled,
    required this.listening,
    required this.onStart,
    required this.onEnd,
  });

  final bool enabled;
  final bool listening;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: listening ? 'Release to stop dictation' : 'Hold to talk',
      child: Semantics(
        button: true,
        enabled: enabled,
        label: listening ? 'Release to stop dictation' : 'Hold to talk',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: enabled ? (_) => onStart() : null,
          onLongPressEnd: enabled ? (_) => onEnd() : null,
          onLongPressCancel: enabled ? onEnd : null,
          child: AnimatedContainer(
            key: const ValueKey('push-to-talk-button'),
            duration: const Duration(milliseconds: 140),
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: listening ? PetTheme.aqua : PetTheme.panel,
              borderRadius: BorderRadius.circular(27),
              border: Border.all(
                color: listening ? PetTheme.aqua : const Color(0xFF303A46),
              ),
            ),
            child: Icon(
              Icons.mic,
              color: listening ? const Color(0xFF10141A) : PetTheme.ivory,
            ),
          ),
        ),
      ),
    );
  }
}

class _TypingComposer extends StatelessWidget {
  const _TypingComposer({
    required this.controller,
    required this.isSending,
    required this.compact,
    required this.onGallery,
    required this.onSend,
    required this.onStop,
    super.key,
  });

  final TextEditingController controller;
  final bool isSending;
  final bool compact;
  final VoidCallback onGallery;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      decoration: BoxDecoration(
        color: PetTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF303A46)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Choose media from gallery',
            visualDensity: compact ? VisualDensity.compact : null,
            onPressed: isSending ? null : onGallery,
            icon: const Icon(Icons.photo_library_outlined),
          ),
          Expanded(
            child: TextField(
              key: const ValueKey('chat-text-field'),
              controller: controller,
              minLines: 1,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Ask about your pet',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
          IconButton.filled(
            tooltip: isSending ? 'Stop response' : 'Send',
            visualDensity: compact ? VisualDensity.compact : null,
            onPressed: isSending
                ? onStop
                : () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    onSend();
                  },
            icon: Icon(isSending ? Icons.stop : Icons.arrow_upward),
          ),
          const SizedBox(width: 5),
        ],
      ),
    );
  }
}

class _ListeningComposer extends StatelessWidget {
  const _ListeningComposer({
    required this.transcript,
    required this.soundLevel,
    super.key,
  });

  final String transcript;
  final double soundLevel;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 76, maxHeight: 142),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
      decoration: BoxDecoration(
        color: const Color(0xFF111B23),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PetTheme.aqua),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              transcript.trim().isEmpty ? 'Listening...' : transcript,
              key: const ValueKey('live-transcript'),
              maxLines: 4,
              overflow: TextOverflow.fade,
              style: const TextStyle(color: PetTheme.ivory, height: 1.25),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(height: 24, child: VoiceWaveform(level: soundLevel)),
        ],
      ),
    );
  }
}

class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({required this.level, super.key});

  final double level;

  @override
  Widget build(BuildContext context) {
    final normalized = level.clamp(0.0, 1.0);
    const pattern = [0.35, 0.6, 0.85, 0.5, 1.0, 0.72, 0.42, 0.9, 0.58, 0.76];
    return Row(
      key: const ValueKey('voice-waveform'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final factor in pattern)
          Expanded(
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOut,
                width: 3,
                height: 4 + (20 * normalized * factor),
                decoration: BoxDecoration(
                  color: Color.lerp(PetTheme.muted, PetTheme.aqua, normalized),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
