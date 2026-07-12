import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/pet_theme.dart';
import '../models/pet_room_state.dart';
import '../view_models/isometric_home_view_model.dart';

const double _expandedLayoutMinWidth = 600;

class IsometricHomePage extends StatefulWidget {
  const IsometricHomePage({
    required this.captureScreenBuilder,
    required this.streakScreenBuilder,
    required this.chatScreenBuilder,
    this.viewModel,
    super.key,
  });

  final WidgetBuilder captureScreenBuilder;
  final WidgetBuilder streakScreenBuilder;
  final WidgetBuilder chatScreenBuilder;
  final IsometricHomeViewModel? viewModel;

  @override
  State<IsometricHomePage> createState() => _IsometricHomePageState();
}

class _IsometricHomePageState extends State<IsometricHomePage>
    with WidgetsBindingObserver {
  late final IsometricHomeViewModel _viewModel;
  late final bool _ownsViewModel;

  @override
  void initState() {
    super.initState();
    _ownsViewModel = widget.viewModel == null;
    _viewModel = widget.viewModel ?? IsometricHomeViewModel();
    WidgetsBinding.instance.addObserver(this);
    _viewModel.startStandby();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _viewModel.resumeStandby();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _viewModel.pauseStandby();
    }
  }

  Future<void> _openDestination(WidgetBuilder builder) async {
    _viewModel.pauseStandby();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
    if (mounted) _viewModel.resumeStandby();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.pauseStandby();
    if (_ownsViewModel) _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              return _PetRoomScene(
                state: _viewModel.state,
                constraints: constraints,
                onPetTap: _viewModel.togglePetStats,
                onOpenCamera: () =>
                    _openDestination(widget.captureScreenBuilder),
                onOpenStreaks: () =>
                    _openDestination(widget.streakScreenBuilder),
                onOpenChat: () =>
                    _openDestination(widget.chatScreenBuilder),
              );
            },
          );
        },
      ),
    );
  }
}

class _PetRoomScene extends StatelessWidget {
  const _PetRoomScene({
    required this.state,
    required this.constraints,
    required this.onPetTap,
    required this.onOpenCamera,
    required this.onOpenStreaks,
    required this.onOpenChat,
  });

  final PetRoomState state;
  final BoxConstraints constraints;
  final ValueChanged<String> onPetTap;
  final VoidCallback onOpenCamera;
  final VoidCallback onOpenStreaks;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final isCompact = constraints.maxWidth < _expandedLayoutMinWidth;
    final sceneExtent = math.min(constraints.maxWidth, constraints.maxHeight);
    final selectedPet = state.selectedPet;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Image.asset(
            state.roomAssets.backgroundAssetPath,
            key: const Key('isometric-room-background'),
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.85,
                colors: [
                  Colors.transparent,
                  const Color(0x77000000),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: InteractiveViewer(
            key: const Key('isometric-room-viewer'),
            minScale: 0.4,
            maxScale: 3,
            boundaryMargin: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth * 0.15, 
              vertical: constraints.maxHeight * 0.4,
            ),
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Center(
                child: Transform.scale(
                  scale: 0.85,
                  child: SizedBox.square(
                    dimension: sceneExtent,
                    child: _ZoomableRoom(state: state, onPetTap: onPetTap),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 16 : 32,
                12,
                isCompact ? 16 : 32,
                0,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _GlassCommandButton(
                  tooltip: 'Open pet moment streak calendar',
                  icon: Icons.local_fire_department_rounded,
                  label: 'Pet Moment Streaks',
                  onPressed: onOpenStreaks,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 12,
          right: isCompact ? 16 : 32,
          child: SafeArea(
            bottom: false,
            child: Tooltip(
              message: 'Open pet agent chat',
              child: IconButton(
                onPressed: onOpenChat,
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                color: Colors.white,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  overlayColor: Colors.white24,
                ),
              ),
            ),
          ),
        ),
        if (selectedPet != null)
          _PositionedPetStatCard(
            stats: selectedPet.stats,
            isCompact: isCompact,
            onOpenCamera: onOpenCamera,
            isWelcomeMode: state.isWelcomeMode,
          ),
      ],
    );
  }
}

class _ZoomableRoom extends StatelessWidget {
  const _ZoomableRoom({required this.state, required this.onPetTap});

  final PetRoomState state;
  final ValueChanged<String> onPetTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final petSize = (constraints.maxWidth * 0.20)
            .clamp(88.0, 184.0)
            .toDouble();

        double petLeft(PetRoomPetState pet) {
          return (pet.normalizedPosition.dx * constraints.maxWidth -
                  petSize / 2)
              .clamp(8.0, math.max(8.0, constraints.maxWidth - petSize - 8))
              .toDouble();
        }

        double petTop(PetRoomPetState pet) {
          return (pet.normalizedPosition.dy * constraints.maxHeight -
                  petSize / 2)
              .clamp(8.0, math.max(8.0, constraints.maxHeight - petSize - 8))
              .toDouble();
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Image.asset(
                state.roomAssets.transparentRoomAssetPath,
                key: const Key('isometric-transparent-room'),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            for (final pet in state.pets)
              _PetSprite(
                petId: pet.id,
                left: petLeft(pet),
                top: petTop(pet),
                size: petSize,
                action: pet.activeAction,
                onTap: () => onPetTap(pet.id),
                label: state.selectedPetId == pet.id
                    ? 'Hide stats for ${pet.stats.name}'
                    : 'Show stats for ${pet.stats.name}',
              ),
          ],
        );
      },
    );
  }
}

class _PetSprite extends StatelessWidget {
  const _PetSprite({
    required this.petId,
    required this.left,
    required this.top,
    required this.size,
    required this.action,
    required this.onTap,
    required this.label,
  });

  final String petId;
  final double left;
  final double top;
  final double size;
  final PetStandbyAction action;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      left: left,
      top: top,
      width: size,
      height: size,
      duration: action.duration,
      curve: Curves.easeInOut,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          key: Key('pet-$petId-sprite'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Image.asset(
            action.assetPath,
            key: ValueKey(action.assetPath),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
          ),
        ),
      ),
    );
  }
}

class _PositionedPetStatCard extends StatelessWidget {
  const _PositionedPetStatCard({
    required this.stats,
    required this.isCompact,
    required this.onOpenCamera,
    required this.isWelcomeMode,
  });

  final PetStats stats;
  final bool isCompact;
  final VoidCallback onOpenCamera;
  final bool isWelcomeMode;

  @override
  Widget build(BuildContext context) {
    final card = _PetStatCard(
      stats: stats,
      onOpenCamera: onOpenCamera,
      isWelcomeMode: isWelcomeMode,
    );
    if (isCompact) {
      return Positioned(left: 16, right: 16, bottom: 20, child: card);
    }
    return Positioned(right: 32, top: 96, width: 320, child: card);
  }
}

class _PetStatCard extends StatelessWidget {
  const _PetStatCard({
    required this.stats,
    required this.onOpenCamera,
    required this.isWelcomeMode,
  });

  final PetStats stats;
  final VoidCallback onOpenCamera;
  final bool isWelcomeMode;

  @override
  Widget build(BuildContext context) {
    final title = isWelcomeMode ? 'Meow...Meow Meow...Moew Meow' : 'Pet Stats';

    return ClipRRect(
      key: const Key('pet-stat-card'),
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x99171B22),
            border: Border.all(color: const Color(0x66FFFFFF)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: PetTheme.ivory,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Open camera',
                      onPressed: onOpenCamera,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0x33FFFFFF),
                        foregroundColor: PetTheme.ivory,
                        minimumSize: const Size.square(44),
                      ),
                      icon: const Icon(Icons.photo_camera_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _StatRow(label: 'Pet Name', value: stats.name),
                const SizedBox(height: 8),
                _StatRow(label: 'Species', value: stats.species),
                const SizedBox(height: 8),
                _StatRow(label: 'Emotion', value: stats.emotion),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: PetTheme.muted)),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: PetTheme.ivory,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassCommandButton extends StatelessWidget {
  const _GlassCommandButton({
    required this.tooltip,
    required this.icon,
    this.label,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final String? label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Tooltip(
          message: tooltip,
          child: label == null || label!.isEmpty
              ? IconButton(
                  onPressed: onPressed,
                  icon: Icon(icon, color: PetTheme.coral),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0x66171B22),
                    foregroundColor: PetTheme.ivory,
                    side: const BorderSide(color: Color(0x66FFFFFF)),
                    minimumSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                )
              : OutlinedButton.icon(
                  onPressed: onPressed,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0x66171B22),
                    foregroundColor: PetTheme.ivory,
                    side: const BorderSide(color: Color(0x66FFFFFF)),
                    minimumSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: Icon(icon, color: PetTheme.coral),
                  label: Text(
                    label!,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
        ),
      ),
    );
  }
}
