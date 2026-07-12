import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/pet_theme.dart';

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    required this.controller,
    required this.isSending,
    required this.isListening,
    required this.soundLevel,
    required this.onGallery,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onTapStart,
    required this.onConfirmListening,
    required this.onCancelListening,
    required this.onSend,
    required this.onStop,
    this.pendingImagePath,
    this.isUploadingImage = false,
    this.onRemoveAttachment,
    super.key,
  });

  final TextEditingController controller;
  final bool isSending;
  final bool isListening;
  final double soundLevel;
  final VoidCallback onGallery;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onTapStart;
  final VoidCallback onConfirmListening;
  final VoidCallback onCancelListening;
  final VoidCallback onSend;
  final VoidCallback onStop;

  /// Local (on-device) file path of a photo the user has attached to the
  /// next chat message. Shown as a small thumbnail above the text field.
  /// This is the lightweight "attach a photo + type a message" flow — it
  /// never opens the full camera/ML capture screen.
  final String? pendingImagePath;

  /// True while the attached photo is being uploaded to the backend so its
  /// server-side path can be threaded into the chat message.
  final bool isUploadingImage;

  /// Called when the user taps the "x" on the attachment thumbnail.
  final VoidCallback? onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    // The voice control stays mounted at all times (only its visual state
    // changes) so a hold-to-talk long-press gesture is never interrupted by
    // a widget swap mid-press. The detailed "listening" panel (transcript +
    // waveform) is rendered separately, centered on screen and away from
    // this control — see AgentChatScreen — so it can never sit on top of
    // it and swallow the pointer-up that ends the long press.
    // Here we only show a lightweight, non-interactive placeholder that
    // keeps this row's height stable while listening.
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _SmartMicButton(
              enabled: !isSending,
              listening: isListening,
              onHoldStart: onHoldStart,
              onHoldEnd: onHoldEnd,
              onTapStart: onTapStart,
              onConfirm: onConfirmListening,
              onCancel: onCancelListening,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: isListening
                    ? const _ListeningPlaceholder(
                        key: ValueKey('listening-placeholder'),
                      )
                    : _TypingComposer(
                        key: const ValueKey('typing-composer'),
                        controller: controller,
                        isSending: isSending,
                        compact: constraints.maxWidth < 360,
                        onGallery: onGallery,
                        onSend: onSend,
                        onStop: onStop,
                        pendingImagePath: pendingImagePath,
                        isUploadingImage: isUploadingImage,
                        onRemoveAttachment: onRemoveAttachment,
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Single mic button that auto-detects intent by press duration.
/// < 100 ms → tap-to-confirm (start listening; show cancel/confirm).
/// ≥ 100 ms → hold-to-talk (listen while held; release to send).
class _SmartMicButton extends StatefulWidget {
  const _SmartMicButton({
    required this.enabled,
    required this.listening,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onTapStart,
    required this.onConfirm,
    required this.onCancel,
  });

  final bool enabled;
  final bool listening;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onTapStart;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  State<_SmartMicButton> createState() => _SmartMicButtonState();
}

class _SmartMicButtonState extends State<_SmartMicButton> {
  DateTime? _pressStart;
  bool _isHolding = false;

  static const _holdThreshold = Duration(milliseconds: 100);

  void _onPointerDown(PointerDownEvent _) {
    if (!widget.enabled) return;
    _pressStart = DateTime.now();
    _isHolding = false;
    // Schedule hold detection after threshold.
    Future.delayed(_holdThreshold, () {
      if (_pressStart == null) return; // already lifted
      _isHolding = true;
      widget.onHoldStart();
    });
  }

  void _onPointerUp(PointerUpEvent _) {
    final start = _pressStart;
    _pressStart = null;
    if (start == null || !widget.enabled) return;
    if (_isHolding) {
      // Hold-to-talk: release ends recording.
      widget.onHoldEnd();
    } else {
      // Tap: start tap-to-confirm flow.
      widget.onTapStart();
    }
    _isHolding = false;
  }

  void _onPointerCancel(PointerCancelEvent _) {
    if (_isHolding) widget.onHoldEnd();
    _pressStart = null;
    _isHolding = false;
  }

  @override
  Widget build(BuildContext context) {
    // While tap-to-confirm is active (listening but not holding), show
    // cancel + confirm buttons instead of the mic.
    if (widget.listening && !_isHolding) {
      return Row(
        key: const ValueKey('tap-confirm-active'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _roundButton(
            key: const ValueKey('voice-cancel-button'),
            tooltip: 'Cancel',
            icon: Icons.close,
            background: PetTheme.panel,
            borderColor: const Color(0xFF303A46),
            iconColor: PetTheme.ivory,
            onTap: widget.onCancel,
          ),
          const SizedBox(width: 8),
          _roundButton(
            key: const ValueKey('voice-confirm-button'),
            tooltip: 'Send',
            icon: Icons.check,
            background: PetTheme.aqua,
            borderColor: PetTheme.aqua,
            iconColor: const Color(0xFF10141A),
            onTap: widget.onConfirm,
          ),
        ],
      );
    }

    final isActive = widget.listening && _isHolding;
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Tooltip(
        message: isActive ? 'Release to send' : 'Tap or hold to talk',
        child: Semantics(
          button: true,
          enabled: widget.enabled,
          label: isActive ? 'Release to send' : 'Tap or hold to talk',
          child: AnimatedContainer(
            key: const ValueKey('smart-mic-button'),
            duration: const Duration(milliseconds: 140),
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: isActive ? PetTheme.aqua : PetTheme.panel,
              borderRadius: BorderRadius.circular(27),
              border: Border.all(
                color: isActive ? PetTheme.aqua : const Color(0xFF303A46),
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: PetTheme.aqua.withValues(alpha: 0.45),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              Icons.mic,
              color: isActive ? const Color(0xFF10141A) : PetTheme.ivory,
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundButton({
    required String tooltip,
    required IconData icon,
    required Color background,
    required Color borderColor,
    required Color iconColor,
    required VoidCallback onTap,
    Key? key,
  }) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkResponse(
          key: key,
          onTap: onTap,
          radius: 30,
          child: Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor),
            ),
            child: Icon(icon, color: iconColor),
          ),
        ),
      ),
    );
  }
}

/// Fills the composer's text-field slot while listening, so the row
/// doesn't jump in height. Purely visual — no gestures here, and it
/// never overlaps the push-to-talk button next to it.
class _ListeningPlaceholder extends StatelessWidget {
  const _ListeningPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: PetTheme.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: PetTheme.aqua),
        ),
        child: Text(
          "Go ahead, I'm listening...",
          style: TextStyle(color: PetTheme.muted),
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
    this.pendingImagePath,
    this.isUploadingImage = false,
    this.onRemoveAttachment,
    super.key,
  });

  final TextEditingController controller;
  final bool isSending;
  final bool compact;
  final VoidCallback onGallery;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final String? pendingImagePath;
  final bool isUploadingImage;
  final VoidCallback? onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pendingImagePath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _AttachmentPreview(
              imagePath: pendingImagePath!,
              isUploading: isUploadingImage,
              onRemove: onRemoveAttachment,
            ),
          ),
        Container(
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
                tooltip: 'Attach a photo',
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
        ),
      ],
    );
  }
}

/// Small thumbnail chip shown above the text field once the user has
/// attached a photo from the gallery. Purely a preview — the actual
/// upload happens as soon as the photo is picked (see
/// AgentChatScreen._pickAttachment), so by the time the message is sent
/// the server-side path is already known.
class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.imagePath,
    required this.isUploading,
    this.onRemove,
  });

  final String imagePath;
  final bool isUploading;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: PetTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF303A46)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(imagePath),
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              ),
              if (isUploading)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Text(
            isUploading ? 'Attaching photo…' : 'Photo attached',
            style: TextStyle(color: PetTheme.muted, fontSize: 13),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove photo',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }
}

/// Shown centered on screen, well away from the push-to-talk button,
/// while the mic is held down. Purely informational and non-interactive —
/// release the button to stop and send. Kept public so it can be rendered
/// from AgentChatScreen's full-screen overlay instead of inline next to
/// the button, so it can never intercept the pointer release that ends
/// the long press.
class VoiceListeningPanel extends StatefulWidget {
  const VoiceListeningPanel({
    required this.transcript,
    required this.soundLevel,
    super.key,
  });

  final String transcript;
  final double soundLevel;

  @override
  State<VoiceListeningPanel> createState() => _VoiceListeningPanelState();
}

class _VoiceListeningPanelState extends State<VoiceListeningPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _swirl;

  @override
  void initState() {
    super.initState();
    _swirl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _swirl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.soundLevel.clamp(0.0, 1.0);
    final hasTranscript = widget.transcript.trim().isNotEmpty;

    return Container(
      constraints: const BoxConstraints(minHeight: 76, maxHeight: 150),
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0E141C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PetTheme.aqua),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _swirl,
            builder: (context, _) {
              return _GlowRing(
                rotation: _swirl.value * 2 * math.pi,
                level: level,
                size: 58,
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasTranscript
                      ? widget.transcript
                      : "Go ahead, I'm listening...",
                  key: const ValueKey('live-transcript'),
                  maxLines: 3,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    color: hasTranscript ? PetTheme.ivory : PetTheme.muted,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(height: 20, child: VoiceWaveform(level: level)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft, rotating glow ring with a pulsing core — a compact echo of a
/// full-screen "listening" orb, sized to sit inline in the composer.
class _GlowRing extends StatelessWidget {
  const _GlowRing({
    required this.rotation,
    required this.level,
    this.size = 84,
  });

  final double rotation;
  final double level;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ringSize = size * 0.78;
    final coreSize = size * 0.42 + (level * size * 0.14);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: ringSize + 12 + (level * 8),
            height: ringSize + 12 + (level * 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: PetTheme.aqua.withValues(alpha: 0.30),
                  blurRadius: size * 0.35,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          Transform.rotate(
            angle: rotation,
            child: Container(
              width: ringSize,
              height: ringSize,
              padding: EdgeInsets.all(size * 0.07),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    PetTheme.aqua.withValues(alpha: 0.05),
                    PetTheme.aqua,
                    PetTheme.aqua.withValues(alpha: 0.10),
                    PetTheme.aqua.withValues(alpha: 0.65),
                    PetTheme.aqua.withValues(alpha: 0.05),
                  ],
                  stops: const [0.0, 0.25, 0.5, 0.78, 1.0],
                ),
              ),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF0E141C),
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: coreSize,
            height: coreSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: PetTheme.aqua.withValues(alpha: 0.18 + level * 0.3),
              boxShadow: [
                BoxShadow(
                  color: PetTheme.aqua.withValues(alpha: 0.55),
                  blurRadius: size * 0.2,
                ),
              ],
            ),
            child: Icon(Icons.mic, color: PetTheme.ivory, size: size * 0.24),
          ),
        ],
      ),
    );
  }
}

class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({required this.level, this.barCount = 10, super.key});

  final double level;
  final int barCount;

  @override
  Widget build(BuildContext context) {
    final normalized = level.clamp(0.0, 1.0);
    const basePattern = [0.35, 0.6, 0.85, 0.5, 1.0, 0.72, 0.42, 0.9, 0.58, 0.76];
    final pattern = List.generate(
      barCount,
      (i) => basePattern[i % basePattern.length],
    );
    return Row(
      key: const ValueKey('voice-waveform'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final factor in pattern)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
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
      ],
    );
  }
}