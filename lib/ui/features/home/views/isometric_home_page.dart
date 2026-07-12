import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/pet_theme.dart';
import '../../../../data/services/agent_stream_client.dart';
import '../../../../data/services/pet_streak_client.dart';
import '../../../../domain/models/owner_profile.dart';
import '../../streak/pet_moment_streak_screen.dart';
import '../models/pet_room_state.dart';
import '../widgets/owner_profile_content.dart';
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

  final Widget Function(BuildContext, String, String) captureScreenBuilder;
  final Widget Function(BuildContext, OwnerProfile?) chatScreenBuilder;
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
  OwnerProfile _ownerProfile = const OwnerProfile(
    name: 'Dickson Lai',
    phone: '+65 8xxx 9460',
    address: '14000 Bukit Mertajam, Pulau Pinang',
  );

  @override
  void initState() {
    super.initState();
    _ownsViewModel = widget.viewModel == null;
    _viewModel =
        widget.viewModel ??
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
    final selectedPet =
        _viewModel.state.selectedPet ?? _viewModel.state.pets.firstOrNull;
    final petId = selectedPet?.id ?? 'pet-01';
    final petName = selectedPet?.stats.name ?? 'Pet';
    await _openDestination(
      (_) => PetMomentStreakScreen(
        streakClient: widget.streakClient!,
        petId: petId,
        petName: petName,
      ),
    );
  }

  Future<void> _showAddPetModal() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<Object>(
      context: context,
      builder: (_) => _AddPetDialog(client: widget.client!),
    );
    if (!mounted) return;
    if (result == 'chat') {
      _openDestination((ctx) => widget.chatScreenBuilder(ctx, _ownerProfile));
    } else if (result is Map<String, String>) {
      try {
        await widget.client!.createPetProfile(result);
        _viewModel.resumeStandby();
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to add pet: $e')),
        );
      }
    }
  }

  Future<void> _showProfileDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: PetTheme.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OwnerProfileContent(
            onSaved: (profile) => setState(() => _ownerProfile = profile),
          ),
        ),
      ),
    );
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
                onOpenCamera: () {
                  final selectedPet =
                      _viewModel.state.selectedPet ??
                      _viewModel.state.pets.firstOrNull;
                  final petId = selectedPet?.id ?? 'pet-01';
                  final petName = selectedPet?.stats.name ?? 'Pet';
                  _openDestination(
                    (context) =>
                        widget.captureScreenBuilder(context, petId, petName),
                  );
                },
                onOpenStreaks: _openStreakScreen,
                onOpenChat: () => _openDestination(
                  (ctx) => widget.chatScreenBuilder(ctx, _ownerProfile),
                ),
                onAddPet: _showAddPetModal,
                onOpenProfile: _showProfileDialog,
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
    required this.onOpenProfile,
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
  final VoidCallback onOpenProfile;
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
                        label:
                            '$streakCount Streak${streakCount! >= 1 ? 's' : ''}',
                        onPressed: onOpenStreaks,
                        iconColor: streakCount! > 0
                            ? PetTheme.coral
                            : PetTheme.muted,
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
                    icon: const Icon(Icons.add_box_outlined),
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      overlayColor: Colors.white24,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Show owner profile',
                  child: IconButton(
                    onPressed: onOpenProfile,
                    icon: const Icon(Icons.person_outline),
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
                _StatRow(
                  label: widget.stats.breed != null ? 'Breed' : 'Species',
                  value: widget.stats.breed ?? widget.stats.species,
                ),
                const SizedBox(height: 8),
                _StatRow(label: 'Mood', value: widget.stats.mood),
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

    if (s.breed != null) addRow('Species', s.species);
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
  static const _speciesOptions = ['Cat', 'Dog', 'Bird', 'Other'];
  static const _lifeStageOptions = ['Baby', 'Young', 'Adult', 'Senior'];

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _customSpeciesCtrl = TextEditingController();
  final _breedCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _conditionsCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _clinicCtrl = TextEditingController();
  final _foodBrandCtrl = TextEditingController();
  final _picker = ImagePicker();

  String _selectedSpecies = 'Cat';
  String? _selectedLifeStage;
  File? _photoFile;
  String? _uploadedImagePath;
  bool _detailsExpanded = false;
  bool _isUploading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _customSpeciesCtrl.dispose();
    _breedCtrl.dispose();
    _weightCtrl.dispose();
    _conditionsCtrl.dispose();
    _addressCtrl.dispose();
    _clinicCtrl.dispose();
    _foodBrandCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_isUploading) return;
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    setState(() {
      _photoFile = File(file.path);
      _uploadedImagePath = null;
    });
  }

  void _removePhoto() {
    if (_isUploading) return;
    setState(() {
      _photoFile = null;
      _uploadedImagePath = null;
    });
  }

  String? _requiredName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter your pet\'s name';
    return null;
  }

  String? _customSpeciesValidator(String? value) {
    if (_selectedSpecies == 'Other' &&
        (value == null || value.trim().isEmpty)) {
      return 'Tell us the species';
    }
    return null;
  }

  String? _weightValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final weight = double.tryParse(text);
    if (weight == null || weight <= 0) {
      return 'Enter a valid weight';
    }
    return null;
  }

  String get _resolvedSpecies {
    if (_selectedSpecies == 'Other') {
      return _customSpeciesCtrl.text.trim();
    }
    return _selectedSpecies;
  }

  void _putOptional(Map<String, String> data, String key, String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) data[key] = trimmed;
  }

  Future<void> _submit() async {
    if (_isUploading || !_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (_photoFile != null) {
      setState(() => _isUploading = true);
      try {
        final uploaded = await widget.client.uploadMedia(_photoFile!);
        _uploadedImagePath = uploaded.path;
      } on MediaUploadException {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Photo upload failed. Try again.')),
        );
        setState(() => _isUploading = false);
        return;
      }
    }

    final data = <String, String>{
      'pet_id': DateTime.now().microsecondsSinceEpoch.toString(),
      'name': _nameCtrl.text.trim(),
      'species': _resolvedSpecies,
    };
    _putOptional(data, 'breed', _breedCtrl.text);
    _putOptional(data, 'weight_kg', _weightCtrl.text);
    _putOptional(data, 'life_stage', _selectedLifeStage);
    _putOptional(data, 'known_conditions', _conditionsCtrl.text);
    _putOptional(data, 'delivery_address', _addressCtrl.text);
    _putOptional(data, 'preferred_clinic', _clinicCtrl.text);
    _putOptional(data, 'preferred_food_brand', _foodBrandCtrl.text);
    _putOptional(data, 'image_path', _uploadedImagePath);

    if (mounted) navigator.pop(data);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= 600;
    final availableHeight = math.max(
      220.0,
      media.size.height - media.viewInsets.bottom - 48,
    );

    return Dialog(
        key: const Key('add-pet-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Material(
              color: const Color(0xF2171B22),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 560,
                  maxHeight: availableHeight,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AddPetHeader(
                      isUploading: _isUploading,
                      onClose: () => Navigator.of(context).pop(),
                    ),
                    const Divider(height: 1, color: Color(0x22FFFFFF)),
                    Flexible(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _PetPhotoPicker(
                                photoFile: _photoFile,
                                enabled: !_isUploading,
                                onChoose: _pickPhoto,
                                onRemove: _removePhoto,
                              ),
                              const SizedBox(height: 24),
                              const _FormSectionHeading(
                                icon: Icons.pets_outlined,
                                title: 'About your pet',
                                subtitle: 'Start with the essentials.',
                              ),
                              const SizedBox(height: 14),
                              _ResponsiveFieldPair(
                                isWide: isWide,
                                first: _PetTextField(
                                  key: const Key('add-pet-name-field'),
                                  controller: _nameCtrl,
                                  label: 'Pet name',
                                  hint: 'e.g. Mochi',
                                  icon: Icons.badge_outlined,
                                  autofocus: true,
                                  textInputAction: TextInputAction.next,
                                  validator: _requiredName,
                                ),
                                second: _PetDropdownField(
                                  key: const Key('add-pet-species-field'),
                                  label: 'Species',
                                  icon: Icons.category_outlined,
                                  value: _selectedSpecies,
                                  items: _speciesOptions,
                                  onChanged: _isUploading
                                      ? null
                                      : (value) {
                                          if (value == null) return;
                                          setState(() {
                                            _selectedSpecies = value;
                                            if (value != 'Other') {
                                              _customSpeciesCtrl.clear();
                                            }
                                          });
                                        },
                                ),
                              ),
                              if (_selectedSpecies == 'Other') ...[
                                const SizedBox(height: 12),
                                _PetTextField(
                                  key: const Key(
                                    'add-pet-custom-species-field',
                                  ),
                                  controller: _customSpeciesCtrl,
                                  label: 'Other species',
                                  hint: 'What kind of pet?',
                                  icon: Icons.edit_outlined,
                                  textInputAction: TextInputAction.next,
                                  validator: _customSpeciesValidator,
                                ),
                              ],
                              const SizedBox(height: 12),
                              _ResponsiveFieldPair(
                                isWide: isWide,
                                first: _PetTextField(
                                  key: const Key('add-pet-breed-field'),
                                  controller: _breedCtrl,
                                  label: 'Breed',
                                  hint: 'Optional',
                                  icon: Icons.fingerprint,
                                  textInputAction: TextInputAction.next,
                                ),
                                second: _PetDropdownField(
                                  key: const Key('add-pet-life-stage-field'),
                                  label: 'Life stage',
                                  icon: Icons.timeline_outlined,
                                  value: _selectedLifeStage,
                                  items: _lifeStageOptions,
                                  hint: 'Select',
                                  onChanged: _isUploading
                                      ? null
                                      : (value) => setState(
                                          () => _selectedLifeStage = value,
                                        ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _PetTextField(
                                key: const Key('add-pet-weight-field'),
                                controller: _weightCtrl,
                                label: 'Weight',
                                hint: 'Optional',
                                icon: Icons.monitor_weight_outlined,
                                suffixText: 'kg',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                textInputAction: TextInputAction.done,
                                validator: _weightValidator,
                              ),
                              const SizedBox(height: 20),
                              _CareDetailsToggle(
                                expanded: _detailsExpanded,
                                onTap: _isUploading
                                    ? null
                                    : () => setState(
                                        () => _detailsExpanded =
                                            !_detailsExpanded,
                                      ),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                                child: _detailsExpanded
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            const _FormSectionHeading(
                                              icon: Icons.favorite_border,
                                              title: 'Care details',
                                              subtitle:
                                                  'Optional information for better recommendations.',
                                            ),
                                            const SizedBox(height: 14),
                                            _PetTextField(
                                              key: const Key(
                                                'add-pet-conditions-field',
                                              ),
                                              controller: _conditionsCtrl,
                                              label: 'Known conditions',
                                              hint:
                                                  'Allergies, medications, or ongoing care',
                                              icon: Icons
                                                  .health_and_safety_outlined,
                                              maxLines: 2,
                                              textInputAction:
                                                  TextInputAction.newline,
                                            ),
                                            const SizedBox(height: 12),
                                            _ResponsiveFieldPair(
                                              isWide: isWide,
                                              first: _PetTextField(
                                                key: const Key(
                                                  'add-pet-clinic-field',
                                                ),
                                                controller: _clinicCtrl,
                                                label: 'Preferred clinic',
                                                hint: 'Optional',
                                                icon: Icons
                                                    .local_hospital_outlined,
                                                textInputAction:
                                                    TextInputAction.next,
                                              ),
                                              second: _PetTextField(
                                                key: const Key(
                                                  'add-pet-food-field',
                                                ),
                                                controller: _foodBrandCtrl,
                                                label: 'Food brand',
                                                hint: 'Optional',
                                                icon: Icons.restaurant_outlined,
                                                textInputAction:
                                                    TextInputAction.next,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            _PetTextField(
                                              key: const Key(
                                                'add-pet-address-field',
                                              ),
                                              controller: _addressCtrl,
                                              label: 'Delivery address',
                                              hint:
                                                  'Where should pet supplies be delivered?',
                                              icon: Icons.location_on_outlined,
                                              maxLines: 2,
                                              textInputAction:
                                                  TextInputAction.newline,
                                            ),
                                          ],
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              const SizedBox(height: 20),
                              _AgentAssistanceCallout(
                                enabled: !_isUploading,
                                onTap: () => Navigator.of(context).pop('chat'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Color(0x22FFFFFF)),
                    _AddPetFooter(
                      isUploading: _isUploading,
                      onCancel: () => Navigator.of(context).pop(),
                      onSubmit: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }
}

class _AddPetHeader extends StatelessWidget {
  const _AddPetHeader({required this.isUploading, required this.onClose});

  final bool isUploading;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 12, 18),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: PetTheme.sage.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const SizedBox.square(
              dimension: 44,
              child: Icon(Icons.pets, color: PetTheme.sage),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add New Pet',
                  style: TextStyle(
                    color: PetTheme.ivory,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Create a profile for more personal care.',
                  style: TextStyle(color: PetTheme.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('add-pet-close-button'),
            tooltip: 'Close',
            onPressed: isUploading ? null : onClose,
            icon: const Icon(Icons.close),
            color: PetTheme.ivory,
          ),
        ],
      ),
    );
  }
}

class _PetPhotoPicker extends StatelessWidget {
  const _PetPhotoPicker({
    required this.photoFile,
    required this.enabled,
    required this.onChoose,
    required this.onRemove,
  });

  final File? photoFile;
  final bool enabled;
  final VoidCallback onChoose;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoFile != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PetTheme.panelSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.square(
                dimension: 88,
                child: hasPhoto
                    ? Image.file(photoFile!, fit: BoxFit.cover)
                    : const ColoredBox(
                        color: Color(0xFF292F39),
                        child: Icon(
                          Icons.photo_camera_outlined,
                          color: PetTheme.muted,
                          size: 30,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasPhoto ? 'Photo selected' : 'Add a pet photo',
                    style: const TextStyle(
                      color: PetTheme.ivory,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Optional, but helpful for recognizing your pet.',
                    style: TextStyle(color: PetTheme.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('add-pet-photo-button'),
                        onPressed: enabled ? onChoose : null,
                        icon: Icon(
                          hasPhoto
                              ? Icons.sync
                              : Icons.add_photo_alternate_outlined,
                          size: 18,
                        ),
                        label: Text(hasPhoto ? 'Replace' : 'Choose photo'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: PetTheme.ivory,
                          side: const BorderSide(color: Color(0x55FFFFFF)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      if (hasPhoto)
                        IconButton(
                          key: const Key('add-pet-remove-photo-button'),
                          tooltip: 'Remove photo',
                          onPressed: enabled ? onRemove : null,
                          icon: const Icon(Icons.delete_outline),
                          color: PetTheme.coral,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormSectionHeading extends StatelessWidget {
  const _FormSectionHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: PetTheme.sage, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: PetTheme.ivory,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: PetTheme.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResponsiveFieldPair extends StatelessWidget {
  const _ResponsiveFieldPair({
    required this.isWide,
    required this.first,
    required this.second,
  });

  final bool isWide;
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (!isWide) {
      return Column(children: [first, const SizedBox(height: 12), second]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }
}

class _PetTextField extends StatelessWidget {
  const _PetTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.suffixText,
    this.keyboardType,
    this.textInputAction,
    this.autofocus = false,
    this.maxLines = 1,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? hint;
  final String? suffixText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final int maxLines;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofocus: autofocus,
      maxLines: maxLines,
      style: const TextStyle(color: PetTheme.ivory, fontSize: 14),
      decoration: _petInputDecoration(
        label: label,
        hint: hint,
        icon: icon,
        suffixText: suffixText,
      ),
      validator: validator,
    );
  }
}

class _PetDropdownField extends StatelessWidget {
  const _PetDropdownField({
    super.key,
    required this.label,
    required this.icon,
    required this.items,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final IconData icon;
  final List<String> items;
  final String? value;
  final ValueChanged<String?>? onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: PetTheme.panelSoft,
      style: const TextStyle(color: PetTheme.ivory, fontSize: 14),
      decoration: _petInputDecoration(label: label, icon: icon),
      hint: hint == null
          ? null
          : Text(hint!, style: const TextStyle(color: PetTheme.muted)),
      items: [
        for (final item in items)
          DropdownMenuItem(value: item, child: Text(item)),
      ],
      onChanged: onChanged,
    );
  }
}

InputDecoration _petInputDecoration({
  required String label,
  required IconData icon,
  String? hint,
  String? suffixText,
}) {
  const radius = BorderRadius.all(Radius.circular(8));
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixText: suffixText,
    prefixIcon: Icon(icon, size: 20),
    filled: true,
    fillColor: PetTheme.panelSoft,
    labelStyle: const TextStyle(color: PetTheme.muted),
    hintStyle: const TextStyle(color: Color(0xFF7E8792)),
    prefixIconColor: PetTheme.muted,
    border: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: Color(0x33FFFFFF)),
    ),
    enabledBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: Color(0x33FFFFFF)),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: PetTheme.sage, width: 1.5),
    ),
    errorBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: PetTheme.coral),
    ),
    focusedErrorBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: PetTheme.coral, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}

class _CareDetailsToggle extends StatelessWidget {
  const _CareDetailsToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('add-pet-care-toggle'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x12FFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(
                Icons.health_and_safety_outlined,
                color: PetTheme.muted,
                size: 20,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Care details',
                  style: TextStyle(
                    color: PetTheme.ivory,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                expanded ? 'Hide' : 'Optional',
                style: const TextStyle(color: PetTheme.muted, fontSize: 12),
              ),
              const SizedBox(width: 4),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: PetTheme.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentAssistanceCallout extends StatelessWidget {
  const _AgentAssistanceCallout({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('add-pet-chat-action'),
      onPressed: enabled ? onTap : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: PetTheme.ivory,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        side: const BorderSide(color: Color(0x33FFFFFF)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: const Icon(Icons.chat_outlined, color: PetTheme.sage),
      label: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chat with Agent',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 2),
          Text(
            'Prefer help? Add your pet through a guided conversation.',
            style: TextStyle(color: PetTheme.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AddPetFooter extends StatelessWidget {
  const _AddPetFooter({
    required this.isUploading,
    required this.onCancel,
    required this.onSubmit,
  });

  final bool isUploading;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const Key('add-pet-cancel-button'),
              onPressed: isUploading ? null : onCancel,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const Key('add-pet-submit-button'),
              onPressed: isUploading ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: PetTheme.sage,
                foregroundColor: const Color(0xFF1A1E26),
              ),
              icon: isUploading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF1A1E26),
                      ),
                    )
                  : const Icon(Icons.pets, size: 18),
              label: Text(isUploading ? 'Uploading' : 'Add Pet'),
            ),
          ],
        ),
      ),
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
