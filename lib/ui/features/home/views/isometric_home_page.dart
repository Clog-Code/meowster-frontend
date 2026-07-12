import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/pet_theme.dart';
import '../../../../data/services/agent_stream_client.dart';
import '../../../../data/services/pet_streak_client.dart';
import '../../streak/pet_moment_streak_screen.dart';
import '../models/pet_room_state.dart';
import '../view_models/isometric_home_view_model.dart';

const double _expandedLayoutMinWidth = 600;

class IsometricHomePage extends StatefulWidget {
  const IsometricHomePage({
    required this.captureScreenBuilder,
    required this.chatScreenBuilder,
    this.viewModel,
    this.client,
    this.streakClient,
    super.key,
  });

  final WidgetBuilder captureScreenBuilder;
  final WidgetBuilder chatScreenBuilder;
  final IsometricHomeViewModel? viewModel;
  final AgentStreamClient? client;
  final PetStreakClient? streakClient;

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
    _viewModel = widget.viewModel ??
        IsometricHomeViewModel(
          client: widget.client,
          streakClient: widget.streakClient,
        );
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

  Future<void> _openStreakScreen() async {
    final petId = _viewModel.state.selectedPetId ??
        _viewModel.state.pets.firstOrNull?.id ??
        'pet-01';
    await _openDestination(
      (_) => PetMomentStreakScreen(
        streakClient: widget.streakClient!,
        petId: petId,
      ),
    );
  }

  Future<void> _showAddPetModal() async {
    final result = await showDialog<Object>(
      context: context,
      builder: (_) => _AddPetDialog(client: widget.client!),
    );
    if (!mounted) return;
    if (result == 'chat') {
      _openDestination(widget.chatScreenBuilder);
    } else if (result is Map<String, String>) {
      try {
        await widget.client!.createPetProfile(result);
        _viewModel.resumeStandby();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to add pet: $e')));
        }
      }
    }
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
                onTapBlank: _viewModel.clearSelection,
                onOpenCamera: () =>
                    _openDestination(widget.captureScreenBuilder),
                onOpenStreaks: _openStreakScreen,
                onOpenChat: () =>
                    _openDestination(widget.chatScreenBuilder),
                onAddPet: _showAddPetModal,
                streakCount: _viewModel.currentStreak,
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
    required this.onTapBlank,
    required this.onOpenCamera,
    required this.onOpenStreaks,
    required this.onOpenChat,
    required this.onAddPet,
    this.streakCount = 0,
  });

  final PetRoomState state;
  final BoxConstraints constraints;
  final ValueChanged<String> onPetTap;
  final VoidCallback onTapBlank;
  final VoidCallback onOpenCamera;
  final VoidCallback onOpenStreaks;
  final VoidCallback onOpenChat;
  final VoidCallback onAddPet;
  final int? streakCount;

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
                colors: [Colors.transparent, const Color(0x77000000)],
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
                    child: _ZoomableRoom(
                      state: state,
                      onPetTap: onPetTap,
                      onTapBlank: onTapBlank,
                    ),
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
                child: streakCount != null
                    ? _GlassCommandButton(
                        tooltip: 'Open pet moment streak calendar',
                        icon: Icons.local_fire_department_rounded,
                        label: '$streakCount Streak${streakCount! >=1 ? 's' : ''}',
                        onPressed: onOpenStreaks,
                        iconColor: streakCount! > 0 ? PetTheme.coral : PetTheme.muted,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        Positioned(
          top: 12,
          right: isCompact ? 16 : 32,
          child: SafeArea(
            bottom: false,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'Add a new pet',
                  child: IconButton(
                    onPressed: onAddPet,
                    icon: const Icon(Icons.add),
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      overlayColor: Colors.white24,
                    ),
                  ),
                ),
                Tooltip(
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
              ],
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
  const _ZoomableRoom({
    required this.state,
    required this.onPetTap,
    required this.onTapBlank,
  });

  final PetRoomState state;
  final ValueChanged<String> onPetTap;
  final VoidCallback onTapBlank;

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
              child: GestureDetector(
                onTap: onTapBlank,
                child: Image.asset(
                  state.roomAssets.transparentRoomAssetPath,
                  key: const Key('isometric-transparent-room'),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
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

class _PetStatCard extends StatefulWidget {
  const _PetStatCard({
    required this.stats,
    required this.onOpenCamera,
    required this.isWelcomeMode,
  });

  final PetStats stats;
  final VoidCallback onOpenCamera;
  final bool isWelcomeMode;

  @override
  State<_PetStatCard> createState() => _PetStatCardState();
}

class _PetStatCardState extends State<_PetStatCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.isWelcomeMode
        ? 'Meow...Meow Meow...Moew Meow'
        : 'Pet Stats';

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
                      onPressed: widget.onOpenCamera,
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
                _StatRow(label: 'Name', value: widget.stats.name),
                const SizedBox(height: 8),
                _StatRow(label: 'Species', value: widget.stats.species),
                const SizedBox(height: 8),
                _StatRow(label: 'Emotion', value: widget.stats.emotion),
                if (_extraStats.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: Color(0x44FFFFFF)),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Row(
                      children: [
                        const Spacer(),
                        Text(
                          _expanded ? 'Show less' : 'Show more',
                          style: const TextStyle(
                            color: PetTheme.muted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          color: PetTheme.muted,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                  if (_expanded) ..._extraStats,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> get _extraStats {
    final s = widget.stats;
    final widgets = <Widget>[];
    void addRow(String label, String value) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(_StatRow(label: label, value: value));
    }

    if (s.breed != null) addRow('Breed', s.breed!);
    if (s.weightKg != null) {
      addRow('Weight', '${s.weightKg!.toStringAsFixed(1)} kg');
    }
    if (s.lifeStage != null) addRow('Life Stage', s.lifeStage!);
    if (s.knownConditions != null && s.knownConditions!.isNotEmpty) {
      addRow('Conditions', s.knownConditions!);
    }
    if (s.preferredClinic != null && s.preferredClinic!.isNotEmpty) {
      addRow('Preferred Clinic', s.preferredClinic!);
    }
    if (s.preferredFoodBrand != null && s.preferredFoodBrand!.isNotEmpty) {
      addRow('Food Brand', s.preferredFoodBrand!);
    }
    if (s.deliveryAddress != null && s.deliveryAddress!.isNotEmpty) {
      addRow('Delivery Address', s.deliveryAddress!);
    }
    return widgets;
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(color: PetTheme.muted)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
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

class _AddPetDialog extends StatefulWidget {
  const _AddPetDialog({required this.client});

  final AgentStreamClient client;

  @override
  State<_AddPetDialog> createState() => _AddPetDialogState();
}

class _AddPetDialogState extends State<_AddPetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _speciesCtrl = TextEditingController(text: 'Cat');
  final _breedCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _lifeStageCtrl = TextEditingController();
  final _conditionsCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _clinicCtrl = TextEditingController();
  final _foodBrandCtrl = TextEditingController();
  final _picker = ImagePicker();

  File? _photoFile;
  String? _uploadedImagePath;
  bool _detailsExpanded = false;
  bool _isUploading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _speciesCtrl.dispose();
    _breedCtrl.dispose();
    _weightCtrl.dispose();
    _lifeStageCtrl.dispose();
    _conditionsCtrl.dispose();
    _addressCtrl.dispose();
    _clinicCtrl.dispose();
    _foodBrandCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _photoFile = File(file.path));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AlertDialog(
          backgroundColor: const Color(0xCC171B22),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0x44FFFFFF)),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: PetTheme.sage.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.pets, color: PetTheme.sage, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'Add New Pet',
                style: TextStyle(
                  color: PetTheme.ivory,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _field('Name', _nameCtrl, autoFocus: true),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: _field('Species', _speciesCtrl)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _pickPhoto,
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(
                            color: PetTheme.panelSoft,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0x33FFFFFF)),
                            image: _photoFile != null
                                ? DecorationImage(
                                    image: FileImage(_photoFile!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _photoFile == null
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.camera_alt_outlined,
                                      color: PetTheme.muted,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Upload photo',
                                      style: TextStyle(
                                        color: PetTheme.muted,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                )
                              : Stack(
                                  alignment: Alignment.topRight,
                                  children: [
                                    const SizedBox.expand(),
                                    Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: GestureDetector(
                                        onTap: () =>
                                            setState(() => _photoFile = null),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            color: Colors.white,
                                            size: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () => setState(
                          () => _detailsExpanded = !_detailsExpanded,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: _detailsExpanded
                                  ? const BorderSide(color: Color(0x22FFFFFF))
                                  : BorderSide.none,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _detailsExpanded
                                    ? 'Hide details'
                                    : 'More details',
                                style: const TextStyle(
                                  color: PetTheme.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                _detailsExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                color: PetTheme.muted,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_detailsExpanded) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _field('Breed', _breedCtrl)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _field(
                                'Weight (kg)',
                                _weightCtrl,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _field('Life Stage', _lifeStageCtrl),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _field(
                                'Known Conditions',
                                _conditionsCtrl,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _field('Delivery Address', _addressCtrl),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _field('Preferred Clinic', _clinicCtrl),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _field('Food Brand', _foodBrandCtrl),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(
                            child: Divider(color: Color(0x33FFFFFF), height: 1),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'OR',
                              style: TextStyle(
                                color: PetTheme.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Expanded(
                            child: Divider(color: Color(0x33FFFFFF), height: 1),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () => Navigator.of(context).pop('chat'),
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x18FFFFFF),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0x22FFFFFF)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: PetTheme.sage.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.chat_outlined,
                                  color: PetTheme.sage,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Chat with Agent',
                                      style: TextStyle(
                                        color: PetTheme.ivory,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Snap a photo and tell the agent its name',
                                      style: TextStyle(
                                        color: PetTheme.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: PetTheme.muted,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                foregroundColor: PetTheme.muted,
                textStyle: const TextStyle(fontSize: 13),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _isUploading
                  ? null
                  : () async {
                      if (!_formKey.currentState!.validate()) return;

                      if (_photoFile != null) {
                        setState(() => _isUploading = true);
                        try {
                          final uploaded = await widget.client.uploadMedia(
                            _photoFile!,
                          );
                          _uploadedImagePath = uploaded.path;
                        } on MediaUploadException {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Photo upload failed. Try again.'),
                            ),
                          );
                          setState(() => _isUploading = false);
                          return;
                        }
                      }

                      final data = <String, String>{
                        'pet_id': DateTime.now().microsecondsSinceEpoch
                            .toString(),
                        'name': _nameCtrl.text,
                        'species': _speciesCtrl.text,
                        if (_breedCtrl.text.isNotEmpty)
                          'breed': _breedCtrl.text,
                        if (_weightCtrl.text.isNotEmpty)
                          'weight_kg': _weightCtrl.text,
                        if (_lifeStageCtrl.text.isNotEmpty)
                          'life_stage': _lifeStageCtrl.text,
                        if (_conditionsCtrl.text.isNotEmpty)
                          'known_conditions': _conditionsCtrl.text,
                        if (_addressCtrl.text.isNotEmpty)
                          'delivery_address': _addressCtrl.text,
                        if (_clinicCtrl.text.isNotEmpty)
                          'preferred_clinic': _clinicCtrl.text,
                        if (_foodBrandCtrl.text.isNotEmpty)
                          'preferred_food_brand': _foodBrandCtrl.text,
                        if (_uploadedImagePath != null)
                          'image_path': _uploadedImagePath!,
                      };
                      if (mounted) Navigator.of(context).pop(data);
                    },
              style: FilledButton.styleFrom(
                backgroundColor: PetTheme.sage,
                foregroundColor: const Color(0xFF1A1E26),
                textStyle: const TextStyle(fontSize: 13),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: _isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF1A1E26),
                      ),
                    )
                  : const Text('Add Pet'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    TextInputType? keyboardType,
    bool autoFocus = false,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      autofocus: autoFocus,
      style: const TextStyle(color: PetTheme.ivory, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: PetTheme.panelSoft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: PetTheme.sage),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        labelStyle: const TextStyle(color: PetTheme.muted, fontSize: 12),
      ),
      validator: (v) {
        if (label == 'Name' && (v == null || v.trim().isEmpty)) {
          return 'Name is required';
        }
        if (label == 'Species' && (v == null || v.trim().isEmpty)) {
          return 'Species is required';
        }
        return null;
      },
    );
  }
}

class _GlassCommandButton extends StatelessWidget {
  const _GlassCommandButton({
    required this.tooltip,
    required this.icon,
    this.label,
    required this.onPressed,
    this.iconColor = PetTheme.coral,
  });

  final String tooltip;
  final IconData icon;
  final String? label;
  final VoidCallback onPressed;
  final Color iconColor;

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
                  icon: Icon(icon, color: iconColor),
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
                  icon: Icon(icon, color: iconColor),
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
