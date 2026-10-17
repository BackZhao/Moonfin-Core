import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_content_analytics_screen.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeAdminSystemApi extends Fake implements AdminSystemApi {
  @override
  Future<Map<String, dynamic>> getItemCounts() async => {
    'MovieCount': 2,
    'SeriesCount': 0,
    'EpisodeCount': 0,
    'AlbumCount': 0,
    'SongCount': 0,
    'MusicVideoCount': 0,
    'BookCount': 0,
    'BoxSetCount': 1,
  };
}

class _FakeLibraryApi extends Fake implements AdminLibraryApi {
  @override
  Future<List<VirtualFolderInfo>> getVirtualFolders() async => const [
    VirtualFolderInfo(name: 'Films', collectionType: 'movies', itemId: 'm1'),
    VirtualFolderInfo(name: 'Camera', collectionType: 'homevideos', itemId: 'h1'),
  ];
}

/// Records the named arguments of every getItems call.
class _FakeItemsApi extends Fake implements ItemsApi {
  final calls = <Map<Symbol, dynamic>>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #getItems) {
      return super.noSuchMethod(invocation);
    }
    calls.add(invocation.namedArguments);
    final fields = invocation.namedArguments[#fields] as String?;
    if (fields == null) {
      return Future.value(<String, dynamic>{'Items': [], 'TotalRecordCount': 2});
    }
    return Future.value(<String, dynamic>{
      'Items': [
        {
          'Genres': ['Drama'],
          'ProductionYear': 2021,
          'MediaSources': [
            {
              'Container': 'mkv',
              'MediaStreams': [
                {'Type': 'Video', 'Codec': 'hevc'},
                {'Type': 'Audio', 'Codec': 'eac3'},
              ],
            },
          ],
        },
      ],
      'TotalRecordCount': 1,
    });
  }
}

void main() {
  late _FakeItemsApi items;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    items = _FakeItemsApi();
    final client = _MockMediaServerClient();
    when(() => client.baseUrl).thenReturn('http://server');
    when(() => client.userId).thenReturn('u1');
    when(() => client.adminSystemApi).thenReturn(_FakeAdminSystemApi());
    when(() => client.adminLibraryApi).thenReturn(_FakeLibraryApi());
    when(() => client.itemsApi).thenReturn(items);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
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
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AdminContentAnalyticsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> typesOf(Map<Symbol, dynamic> call) =>
      (call[#includeItemTypes] as List<String>?) ?? const [];

  testWidgets('insights ask GET /Items with real ItemFields only', (
    tester,
  ) async {
    await pump(tester);

    final insights = items.calls.where((c) => c[#fields] != null).toList();
    expect(insights, hasLength(1));
    expect(insights.single[#serverWide], isTrue);
    expect(insights.single[#parentId], 'm1');
    expect(insights.single[#fields], 'Genres,MediaSources,MediaStreams');
    expect(find.text('Films'), findsWidgets);
  });

  testWidgets('home videos count videos and photos, collections need no /Items', (
    tester,
  ) async {
    await pump(tester);

    final camera = items.calls
        .where((c) => c[#parentId] == 'h1')
        .map(typesOf)
        .toList();
    expect(camera, unorderedEquals([['Video'], ['Photo']]));
    // BoxSetCount comes from /Items/Counts, and the summary asks nothing else.
    final serverWide = items.calls.where((c) => c[#parentId] == null);
    expect(serverWide, isEmpty);
  });
}
