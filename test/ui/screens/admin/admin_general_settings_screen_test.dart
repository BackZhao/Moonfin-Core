import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/settings/admin_general_settings_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

/// Serves a config, records every post, and can change underneath the page
/// the way another admin or client would.
class _FakeSystemApi extends Fake implements AdminSystemApi {
  Map<String, dynamic> server = {
    'ServerName': 'Moonbase',
    'UICulture': 'en-US',
    'QuickConnectAvailable': true,
    'EnableSlowResponseWarning': true,
    'SlowResponseThresholdMs': 500,
    'LibraryScanFanoutConcurrency': 0,
    'ParallelImageEncodingLimit': 0,
    'CachePath': '/cache',
    'MetadataPath': '/config/metadata',
    'PreferredMetadataLanguage': 'en',
    'MetadataCountryCode': 'US',
    'MinResumePct': 5,
  };
  final posted = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> getServerConfiguration() async =>
      Map<String, dynamic>.from(server);

  @override
  Future<void> updateServerConfiguration(Map<String, dynamic> config) async {
    posted.add(config);
    server = Map<String, dynamic>.from(config);
  }

  @override
  Future<List<Map<String, dynamic>>> getCultures() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getCountries() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getLocalizationOptions() async => const [];
}

void main() {
  late _FakeSystemApi api;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakeSystemApi();
    final client = _MockMediaServerClient();
    when(() => client.adminSystemApi).thenReturn(api);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    AdminDraft.active.value = null;
    await GetIt.instance.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AdminGeneralSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Padding)).first,
    matching: find.byType(TextFormField),
  );

  testWidgets('an edit marks the page dirty and save posts it', (tester) async {
    await pump(tester);
    final draft = AdminDraft.active.value!;
    expect(draft.isDirty, isFalse);

    await tester.enterText(field(l10n.adminGeneralServerName), 'Renamed');
    await tester.pump();
    expect(draft.isDirty, isTrue);

    expect(await draft.save(), isTrue);
    expect(api.posted.single['ServerName'], 'Renamed');
    expect(draft.isDirty, isFalse);
  });

  testWidgets('save keeps keys another page changed meanwhile', (tester) async {
    await pump(tester);
    await tester.enterText(field(l10n.adminGeneralServerName), 'Renamed');
    await tester.pump();

    // The resume page saved in between, and this page never loaded that value.
    api.server = {...api.server, 'MinResumePct': 9};
    await AdminDraft.active.value!.save();

    expect(api.posted.single['MinResumePct'], 9);
    expect(api.posted.single['ServerName'], 'Renamed');
  });

  testWidgets('discard puts the field back', (tester) async {
    await pump(tester);
    await tester.enterText(field(l10n.adminGeneralServerName), 'Renamed');
    await tester.pump();

    AdminDraft.active.value!.discard();
    await tester.pumpAndSettle();

    expect(find.text('Moonbase'), findsOneWidget);
    expect(api.posted, isEmpty);
  });

  testWidgets('the threshold is greyed out while the warning is off', (
    tester,
  ) async {
    api.server = {...api.server, 'EnableSlowResponseWarning': false};
    await pump(tester);

    final threshold = tester.widget<TextField>(
      find.descendant(
        of: field(l10n.adminGeneralSlowResponseThreshold),
        matching: find.byType(TextField),
      ),
    );
    expect(threshold.enabled, isFalse);
  });

  testWidgets('a cleared threshold saves the server default, never 0', (
    tester,
  ) async {
    api.server = {...api.server, 'SlowResponseThresholdMs': 900};
    await pump(tester);
    await tester.enterText(field(l10n.adminGeneralSlowResponseThreshold), '');
    await tester.pump();

    expect(await AdminDraft.active.value!.save(), isTrue);
    expect(api.posted.single['SlowResponseThresholdMs'], 500);
  });

  // Keying the field on its value would rebuild it once the first keystroke
  // makes the page dirty, and drop focus.
  testWidgets('a path field keeps focus while typing', (tester) async {
    await pump(tester);
    final path = field(l10n.adminGeneralCachePath);
    await tester.enterText(path, '/cache2');
    await tester.pump();

    final input = tester.widget<EditableText>(
      find.descendant(of: path, matching: find.byType(EditableText)),
    );
    expect(input.focusNode.hasFocus, isTrue);
    expect(AdminDraft.active.value!.targets['main']!.working['CachePath'],
        '/cache2');
  });

  testWidgets('the page has no save button of its own', (tester) async {
    await pump(tester);
    expect(find.widgetWithText(FilledButton, l10n.save), findsNothing);
  });
}
