import 'dart:io';

import 'package:amd_pet_frontend/app/pet_agent_app.dart';
import 'package:amd_pet_frontend/data/services/agent_stream_client.dart';
import 'package:amd_pet_frontend/data/services/pet_streak_client.dart';
import 'package:amd_pet_frontend/domain/models/pet_streak_summary.dart';
import 'package:amd_pet_frontend/ui/features/home/models/pet_room_state.dart';
import 'package:amd_pet_frontend/ui/features/home/view_models/isometric_home_view_model.dart';
import 'package:amd_pet_frontend/ui/features/home/views/isometric_home_page.dart';
import 'package:amd_pet_frontend/ui/features/streak/pet_moment_streak_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildTestApp(
  IsometricHomeViewModel viewModel, {
  AgentStreamClient? client,
}) {
  return MaterialApp(
    home: IsometricHomePage(
      viewModel: viewModel,
      client: client,
      streakClient: const EmptyPetStreakClient(),
      captureScreenBuilder: (context, _, _) =>
          const Scaffold(body: Center(child: Text('Camera destination'))),
      chatScreenBuilder: (context, _) =>
          const Scaffold(body: Center(child: Text('Chat destination'))),
    ),
  );
}

Finder _formField(Key key) {
  return find.descendant(
    of: find.byKey(key),
    matching: find.byType(TextFormField),
  );
}

Future<void> _openAddPetDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add a new pet'));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('add-pet-dialog')), findsOneWidget);
}

PetRoomPetState _makePet(
  String id,
  String name, {
  String mood = 'Sleepy',
  Offset? position,
}) {
  return PetRoomPetState(
    id: id,
    stats: PetStats(name: name, species: 'Cat', mood: mood),
    activeAction: standbyActionById(PetStandbyActionId.sleepAndWake),
    normalizedPosition: position ?? const Offset(0.54, 0.72),
  );
}

void main() {
  testWidgets('renders paired room layers and two pets', (tester) async {
    final viewModel = IsometricHomeViewModel(
      clock: () => DateTime(2026, 7, 11, 12),
      initialPets: [
        _makePet('mochi', 'Mochi', position: const Offset(0.50, 0.74)),
        _makePet('luna', 'Luna', position: const Offset(0.66, 0.66)),
      ],
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(_buildTestApp(viewModel));
    await tester.pump();

    final background = tester.widget<Image>(
      find.byKey(const Key('isometric-room-background')),
    );
    expect(background.image, isA<AssetImage>());
    expect(
      (background.image as AssetImage).assetName,
      brightNoonRoomAssets.backgroundAssetPath,
    );
    final transparentRoom = tester.widget<Image>(
      find.byKey(const Key('isometric-transparent-room')),
    );
    expect(
      (transparentRoom.image as AssetImage).assetName,
      brightNoonRoomAssets.transparentRoomAssetPath,
    );
    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const Key('isometric-room-viewer')),
    );
    expect(viewer.minScale, 0.4);
    expect(viewer.maxScale, 3);
    expect(find.byKey(const Key('pet-mochi-sprite')), findsOneWidget);
    expect(find.byKey(const Key('pet-luna-sprite')), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey(
          'assets/images/cat-animations/'
          'sprite-animation-8-sleep.gif',
        ),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('pet tap toggles the glass stat card', (tester) async {
    final viewModel = IsometricHomeViewModel(
      initialPets: [
        _makePet('mochi', 'Mochi', position: const Offset(0.50, 0.74)),
        _makePet('luna', 'Luna', position: const Offset(0.66, 0.66)),
      ],
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(_buildTestApp(viewModel));
    await tester.pump();

    expect(find.byKey(const Key('pet-stat-card')), findsNothing);

    await tester.tap(find.byKey(const Key('pet-mochi-sprite')));
    await tester.pump();

    expect(find.byKey(const Key('pet-stat-card')), findsOneWidget);
    expect(find.text('Mochi'), findsOneWidget);
    expect(find.text('Cat'), findsOneWidget);
    expect(find.text('Sleepy'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pet-mochi-sprite')));
    await tester.pump();

    expect(find.byKey(const Key('pet-stat-card')), findsNothing);
  });

  testWidgets('each pet opens its own stats', (tester) async {
    final viewModel = IsometricHomeViewModel(
      initialPets: [
        _makePet('mochi', 'Mochi', position: const Offset(0.50, 0.74)),
        _makePet(
          'luna',
          'Luna',
          mood: 'Curious',
          position: const Offset(0.66, 0.66),
        ),
      ],
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(_buildTestApp(viewModel));

    await tester.tap(find.byKey(const Key('pet-mochi-sprite')));
    await tester.pump();
    expect(find.text('Mochi'), findsOneWidget);
    expect(find.text('Sleepy'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pet-luna-sprite')));
    await tester.pump();
    expect(find.text('Luna'), findsOneWidget);
    expect(find.text('Curious'), findsOneWidget);
    expect(find.text('Mochi'), findsNothing);
  });

  testWidgets('fixed overlays navigate to streaks and camera', (tester) async {
    final viewModel = IsometricHomeViewModel(
      streakClient: const EmptyPetStreakClient(),
      initialPets: [
        _makePet('mochi', 'Mochi', position: const Offset(0.50, 0.74)),
        _makePet('luna', 'Luna', position: const Offset(0.66, 0.66)),
      ],
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(_buildTestApp(viewModel));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pet-mochi-sprite')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open pet moment streak calendar'));
    await tester.pumpAndSettle();
    expect(find.byType(PetMomentStreakScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(PetMomentStreakScreen))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open camera'));
    await tester.pumpAndSettle();
    expect(find.text('Camera destination'), findsOneWidget);
  });

  testWidgets('streak badge stays hidden until a pet is selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      PetAgentApp(
        client: StaticAgentClient(
          pets: const [
            {'pet_id': 'mochi', 'name': 'Mochi', 'species': 'Cat'},
          ],
        ),
        streakClient: FixedStreakClient(
          summary: PetStreakSummary(
            currentStreak: 4,
            longestStreak: 9,
            monthStart: DateTime(2026, 7),
            days: [],
          ),
        ),
        enableCamera: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Open pet moment streak calendar'), findsNothing);
    expect(find.text('4 Streaks'), findsNothing);

    await tester.tap(find.byKey(const Key('pet-mochi-sprite')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Open pet moment streak calendar'), findsOneWidget);
    expect(find.text('4 Streaks'), findsOneWidget);
  });

  testWidgets('add pet form validates required and numeric fields', (
    tester,
  ) async {
    final client = StaticAgentClient();
    final viewModel = IsometricHomeViewModel(
      initialPets: [_makePet('mochi', 'Mochi')],
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(_buildTestApp(viewModel, client: client));
    await _openAddPetDialog(tester);

    await tester.tap(find.byKey(const Key('add-pet-submit-button')));
    await tester.pump();
    expect(find.text("Enter your pet's name"), findsOneWidget);

    await tester.enterText(
      _formField(const Key('add-pet-name-field')),
      'Pepper',
    );
    await tester.tap(find.byKey(const Key('add-pet-species-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-pet-submit-button')));
    await tester.pump();
    expect(find.text('Tell us the species'), findsOneWidget);

    await tester.enterText(
      _formField(const Key('add-pet-custom-species-field')),
      'Rabbit',
    );
    await tester.ensureVisible(find.byKey(const Key('add-pet-weight-field')));
    await tester.enterText(_formField(const Key('add-pet-weight-field')), '-2');
    await tester.tap(find.byKey(const Key('add-pet-submit-button')));
    await tester.pump();
    expect(find.text('Enter a valid weight'), findsOneWidget);
    expect(client.createdProfiles, isEmpty);
  });

  testWidgets('add pet form returns a trimmed profile payload', (tester) async {
    final client = StaticAgentClient();
    final viewModel = IsometricHomeViewModel(
      initialPets: [_makePet('mochi', 'Mochi')],
    );
    await tester.pumpWidget(_buildTestApp(viewModel, client: client));
    await _openAddPetDialog(tester);

    await tester.enterText(
      _formField(const Key('add-pet-name-field')),
      '  Pepper  ',
    );
    await tester.enterText(
      _formField(const Key('add-pet-breed-field')),
      '  Holland Lop  ',
    );
    await tester.ensureVisible(find.byKey(const Key('add-pet-species-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-pet-species-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      _formField(const Key('add-pet-custom-species-field')),
      '  Rabbit  ',
    );
    await tester.ensureVisible(
      find.byKey(const Key('add-pet-life-stage-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-pet-life-stage-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adult').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      _formField(const Key('add-pet-weight-field')),
      '2.4',
    );

    await tester.ensureVisible(find.byKey(const Key('add-pet-care-toggle')));
    await tester.tap(find.byKey(const Key('add-pet-care-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-pet-conditions-field')), findsOneWidget);
    await tester.enterText(
      _formField(const Key('add-pet-conditions-field')),
      '  None  ',
    );

    await tester.tap(find.byKey(const Key('add-pet-submit-button')));
    await tester.pumpAndSettle();

    expect(client.createdProfiles, hasLength(1));
    final profile = client.createdProfiles.single;
    expect(profile['name'], 'Pepper');
    expect(profile['species'], 'Rabbit');
    expect(profile['breed'], 'Holland Lop');
    expect(profile['life_stage'], 'Adult');
    expect(profile['weight_kg'], '2.4');
    expect(profile['known_conditions'], 'None');

    viewModel.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('add pet agent callout opens guided chat', (tester) async {
    final client = StaticAgentClient();
    final viewModel = IsometricHomeViewModel(
      initialPets: [_makePet('mochi', 'Mochi')],
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(_buildTestApp(viewModel, client: client));
    await _openAddPetDialog(tester);

    await tester.ensureVisible(find.byKey(const Key('add-pet-chat-action')));
    await tester.tap(find.byKey(const Key('add-pet-chat-action')));
    await tester.pumpAndSettle();

    expect(find.text('Chat destination'), findsOneWidget);
  });

  testWidgets('add pet dialog fits a compact viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = StaticAgentClient();
    final viewModel = IsometricHomeViewModel(
      initialPets: [_makePet('mochi', 'Mochi')],
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(_buildTestApp(viewModel, client: client));

    await _openAddPetDialog(tester);
    await tester.ensureVisible(find.byKey(const Key('add-pet-care-toggle')));
    await tester.tap(find.byKey(const Key('add-pet-care-toggle')));
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.takeException(), isNull);
  });

  testWidgets('add pet dialog uses paired fields on a wide viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = StaticAgentClient();
    final viewModel = IsometricHomeViewModel(
      initialPets: [_makePet('mochi', 'Mochi')],
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(_buildTestApp(viewModel, client: client));

    await _openAddPetDialog(tester);

    final nameTop = tester.getTopLeft(
      find.byKey(const Key('add-pet-name-field')),
    );
    final speciesTop = tester.getTopLeft(
      find.byKey(const Key('add-pet-species-field')),
    );
    expect(nameTop.dy, speciesTop.dy);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded layout remains overflow-free', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = IsometricHomeViewModel(
      initialPets: [
        _makePet('mochi', 'Mochi', position: const Offset(0.50, 0.74)),
      ],
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(_buildTestApp(viewModel));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pet-mochi-sprite')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pet-stat-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class StaticAgentClient implements AgentStreamClient {
  StaticAgentClient({this.pets = const [], this.petProfiles = const {}});

  final List<Map<String, dynamic>> pets;
  final Map<String, Map<String, dynamic>> petProfiles;
  final List<Map<String, String>> createdProfiles = [];

  @override
  Future<List<ChatThreadSummary>> fetchThreads({int limit = 50}) async => [];

  @override
  Future<List<ChatMessage>> fetchThreadMessages(String threadId) async => [];

  @override
  Future<List<Map<String, dynamic>>> fetchPetProfiles() async => pets;

  @override
  Future<Map<String, dynamic>?> fetchPetProfile(String petId) async {
    return petProfiles[petId];
  }

  @override
  Future<void> createPetProfile(Map<String, String> profile) async {
    createdProfiles.add(Map.unmodifiable(profile));
  }

  @override
  Future<UploadedMedia> uploadMedia(File file) async {
    return UploadedMedia(url: '', path: file.path);
  }

  @override
  Future<void> streamAgent({
    required String path,
    required Map<String, dynamic> payload,
    required void Function(AgentStreamEvent event) onEvent,
  }) async {}
}

class FixedStreakClient implements PetStreakClient {
  const FixedStreakClient({required this.summary});

  final PetStreakSummary summary;

  @override
  Future<PetStreakSummary> fetchStreakSummary({String petId = 'pet-01'}) async {
    return summary;
  }
}
