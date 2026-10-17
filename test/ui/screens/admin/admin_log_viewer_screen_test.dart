import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/logs/admin_log_viewer_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

/// Serves GET /System/Logs/Log, growing by one line per read like a log
/// the server is still writing.
class _FakeSystemApi extends Fake implements AdminSystemApi {
  final names = <String>[];

  @override
  Future<String> getLogFileContent(String name) async {
    names.add(name);
    return List.generate(
      80 + names.length,
      (i) => '[12:00:00] [INF] line $i',
    ).join('\n');
  }
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

  tearDown(() => GetIt.instance.reset());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: AdminLogViewerScreen(fileName: 'log_20261002.log'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('watch refetches every 2 s and follows the end', (tester) async {
    await pump(tester);
    expect(api.names, ['log_20261002.log']);

    await tester.pump(const Duration(seconds: 3));
    expect(api.names, hasLength(1));

    await tester.tap(find.byTooltip(l10n.adminLogWatch));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(api.names, hasLength(2));
    expect(find.text('[12:00:00] [INF] line 81', findRichText: true),
        findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(api.names, hasLength(3));
    expect(find.text('[12:00:00] [INF] line 82', findRichText: true),
        findsOneWidget);

    await tester.tap(find.byTooltip(l10n.adminLogStopWatching));
    await tester.pump(const Duration(seconds: 4));
    expect(api.names, hasLength(3));
  });
}
