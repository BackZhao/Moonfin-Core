// Opens every admin page against a real Jellyfin server and saves each
// settings page once through the UI, logging every request. Skips unless the
// server is configured:
//
//   MOONFIN_LIVE_URL=<server url> MOONFIN_LIVE_TOKEN=<admin token> \
//   MOONFIN_LIVE_USER_ID=<admin user id> \
//   dbus-run-session -- flutter test integration_test/admin -d linux
//
// The saves put back what they change, but run them on a disposable server.
// MOONFIN_LIVE_LOG names a file to write the request log to (JSON lines), and
// MOONFIN_LIVE_SHOTS names a folder to save a screenshot of each page in.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moonfin/data/services/socket_handler.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/admin_routes.dart';
import 'package:moonfin/ui/screens/admin/widgets/admin_settings_search.dart';
import 'package:moonfin/ui/theme/app_theme.dart';
import 'package:moonfin_design/moonfin_design.dart' show ThemeRegistry;
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';

class _Request {
  _Request(this.page, this.method, this.path, this.query, this.status);
  final String page;
  final String method;
  final String path;
  final Map<String, dynamic> query;
  int? status;

  Map<String, dynamic> toJson() => {
    'page': page,
    'method': method,
    'path': path,
    'query': query.map((k, v) => MapEntry(k, '$v')),
    'status': status,
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final url = env['MOONFIN_LIVE_URL'];
  final token = env['MOONFIN_LIVE_TOKEN'];
  final userId = env['MOONFIN_LIVE_USER_ID'];
  final skip = url == null || token == null || userId == null
      ? 'set MOONFIN_LIVE_URL, MOONFIN_LIVE_TOKEN and MOONFIN_LIVE_USER_ID'
      : null;

  final log = <_Request>[];
  var currentPage = '';
  late JellyfinMediaServerClient client;
  final ids = <String, String>{};

  setUpAll(() async {
    if (skip != null) return;
    client = JellyfinMediaServerClient(
      baseUrl: url!,
      deviceInfo: const DeviceInfo(
        id: 'moonfin-admin-live-test',
        name: 'Admin live test',
        appName: 'Moonfin',
        appVersion: 'test',
      ),
      interceptors: [
        InterceptorsWrapper(
          onRequest: (o, h) {
            o.extra['_log'] = _Request(
              currentPage,
              o.method,
              o.uri.path,
              {...o.uri.queryParameters}
                ..removeWhere((k, _) => k.toLowerCase().contains('apikey')),
              null,
            );
            log.add(o.extra['_log'] as _Request);
            h.next(o);
          },
          onResponse: (r, h) {
            (r.requestOptions.extra['_log'] as _Request?)?.status = r.statusCode;
            h.next(r);
          },
          onError: (e, h) {
            (e.requestOptions.extra['_log'] as _Request?)?.status =
                e.response?.statusCode ?? -1;
            h.next(e);
          },
        ),
      ],
    )
      ..accessToken = token
      ..userId = userId;
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    final socket = SocketHandler()..connectTo(client);
    GetIt.instance.registerSingleton<SocketHandler>(socket);

    // Real ids for the pages that need one.
    final users = await client.adminUsersApi.getUsers();
    ids['user'] = users.firstWhere((u) => u.name == 'viewer').id;
    final libraries = await client.adminLibraryApi.getVirtualFolders();
    ids['library'] = libraries.firstWhere((l) => l.name == 'Movies').itemId;
    final tasks = await client.adminTasksApi.getTasks(isHidden: false);
    ids['task'] = tasks.firstWhere((t) => t['Key'] == 'RefreshGuide')['Id'] as String;
    final plugins = await client.adminPluginsApi.getInstalledPlugins();
    ids['plugin'] = plugins.first.id;
    final logs = await client.adminSystemApi.getLogFiles();
    ids['log'] = logs.first.name;
    final items = await client.itemsApi.getItems(
      searchTerm: 'Big Buck Bunny',
      includeItemTypes: const ['Movie'],
      recursive: true,
    );
    ids['item'] = ((items['Items'] as List).first as Map)['Id'] as String;
  });

  tearDownAll(() async {
    if (skip != null) return;
    final out = env['MOONFIN_LIVE_LOG'];
    if (out != null) {
      File(out).writeAsStringSync(
        log.map((r) => jsonEncode(r.toJson())).join('\n'),
      );
    }
  });

  late AppLocalizations l10n;

  final shotKey = GlobalKey();

  Future<GoRouter> pumpAdmin(
    WidgetTester tester,
    String location, {
    Size size = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(path: Destinations.home, builder: (_, _) => const SizedBox()),
        adminShellRoute,
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: RepaintBoundary(
          key: shotKey,
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.buildTheme(ThemeRegistry.active),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      ),
    );
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    return router;
  }

  /// Saves the window as <MOONFIN_LIVE_SHOTS>/<name>.png for review, when set.
  Future<void> shot(String name) async {
    final dir = env['MOONFIN_LIVE_SHOTS'];
    if (dir == null) return;
    final boundary =
        shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  }

  /// Real requests take real time, so pump until nothing is loading.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          i > 5) {
        return;
      }
    }
  }

  void expectNoFailures(String page) {
    final failed = log
        .where((r) => r.page == page && r.status != null && r.status! >= 400 ||
            r.page == page && r.status == -1)
        .map((r) => '${r.method} ${r.path} ${r.status}')
        .toList();
    expect(failed, isEmpty, reason: '$page made failing requests');
    // Still waiting when the test moved on (the plugin catalog comes from the
    // internet), so neither passed nor failed.
    final pending = log.where((r) => r.page == page && r.status == null);
    for (final r in pending) {
      debugPrint('PENDING $page ${r.method} ${r.path}');
    }
  }

  final pages = <String, String Function()>{
    'dashboard': () => Destinations.admin,
    'analytics': () => Destinations.adminAnalytics,
    'activity': () => Destinations.adminActivity,
    'tasks': () => Destinations.adminTasks,
    'task-detail': () => Destinations.adminTask(ids['task']!),
    'libraries': () => Destinations.adminLibraries,
    'library-add': () => Destinations.adminLibrariesAdd,
    'library-edit': () => Destinations.adminLibrary(ids['library']!),
    'display': () => Destinations.adminSettingsDisplay,
    'metadata': () => Destinations.adminSettingsMetadata,
    'nfo': () => Destinations.adminSettingsNfo,
    'metadata-edit': () => Destinations.adminMetadata(ids['item']!),
    'live-tv': () => Destinations.adminLiveTv,
    'transcoding': () => Destinations.adminSettingsPlayback,
    'resume': () => Destinations.adminSettingsResume,
    'streaming': () => Destinations.adminSettingsStreaming,
    'trickplay': () => Destinations.adminSettingsTrickplay,
    'users': () => Destinations.adminUsers,
    'user-add': () => Destinations.adminUsersAdd,
    'user-edit': () => Destinations.adminUser(ids['user']!),
    'devices': () => Destinations.adminDevices,
    'api-keys': () => Destinations.adminKeys,
    'settings': () => Destinations.adminSettings,
    'branding': () => Destinations.adminSettingsBranding,
    'networking': () => Destinations.adminSettingsNetworking,
    'plugins': () => Destinations.adminPlugins,
    'plugin-detail': () => Destinations.adminPlugin(ids['plugin']!),
    'repositories': () => Destinations.adminRepositories,
    'backups': () => Destinations.adminBackups,
    'logs': () => Destinations.adminLogs,
    'log-viewer': () => Destinations.adminLogFile(ids['log']!),
    for (final g in ['overview', 'library', 'playback', 'people', 'system'])
      'group-$g': () => Destinations.adminGroupPath(g),
  };

  for (final entry in pages.entries) {
    testWidgets('${entry.key} opens with live data', skip: skip != null, (
      tester,
    ) async {
      currentPage = entry.key;
      await pumpAdmin(tester, entry.value());
      await settle(tester);
      // The plugin pages wait on the online catalog.
      if (entry.key.startsWith('plugin')) {
        await tester.pump(const Duration(seconds: 10));
        await settle(tester);
      }

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.adminSettingsLoadFailed), findsNothing);
      expectNoFailures(entry.key);
      await shot('desktop-${entry.key}');
      AdminDraft.active.value = null;
    });
  }

  // The phone layout: group tabs along the bottom, a page list per group.
  for (final key in [
    'dashboard',
    for (final g in ['overview', 'library', 'playback', 'people', 'system'])
      'group-$g',
    'settings',
    'live-tv',
    'user-edit',
    'library-edit',
    'metadata-edit',
  ]) {
    testWidgets('$key opens on a phone', skip: skip != null, (tester) async {
      currentPage = '$key:phone';
      await pumpAdmin(tester, pages[key]!(), size: const Size(390, 844));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text(l10n.adminSettingsLoadFailed), findsNothing);
      expectNoFailures(currentPage);
      await shot('phone-$key');
      AdminDraft.active.value = null;
    });
  }

  // The dashboard subscribes to sessions and scheduled tasks, but the server
  // pushes only on events, so a capabilities report and a quick task stand in
  // for a client starting up and a task running.
  testWidgets('the dashboard gets pushed sessions and tasks', skip: skip != null, (
    tester,
  ) async {
    currentPage = 'dashboard:feeds';
    final pushed = <Type>{};
    final sub = GetIt.instance<SocketHandler>().events.listen(
      (e) => pushed.add(e.runtimeType),
    );
    addTearDown(sub.cancel);
    await pumpAdmin(tester, Destinations.admin);
    await settle(tester);
    await client.sessionApi.reportCapabilities({
      'PlayableMediaTypes': ['Video'],
      'SupportedCommands': <String>[],
      'SupportsMediaControl': false,
    });
    final tasks = await client.adminTasksApi.getTasks(isHidden: false);
    await client.adminTasksApi.startTask(
      tasks.firstWhere((t) => t['Key'] == 'DeleteTranscodeFiles')['Id'] as String,
    );
    const feeds = [SessionsMessage, ScheduledTasksInfoMessage];
    for (var i = 0; i < 150 && !pushed.containsAll(feeds); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(pushed, containsAll(feeds));
    AdminDraft.active.value = null;
  });

  // Each settings page saves once through the bar: flip its first switch (or
  // edit its first text field), save, check the post went through, then put
  // it back and save again.
  final draftPages = {
    'settings': const _Save('POST', '/System/Configuration'),
    'display': const _Save('POST', '/System/Configuration'),
    'metadata': const _Save('POST', '/System/Configuration'),
    'nfo': const _Save('POST', '/System/Configuration/xbmcmetadata'),
    'transcoding': const _Save('POST', '/System/Configuration/encoding'),
    'resume': const _Save('POST', '/System/Configuration'),
    'streaming': const _Save('POST', '/System/Configuration', text: true),
    'trickplay': const _Save('POST', '/System/Configuration'),
    // Branding's first switch (the splash screen) saves at once and stays out
    // of the draft, so this edits a text field.
    'branding': const _Save('POST', '/System/Configuration/branding', text: true),
    'networking': const _Save('POST', '/System/Configuration/network'),
    // The server refuses a recording path that doesn't exist.
    'live-tv': _Save(
      'POST',
      '/System/Configuration/livetv',
      tab: (l) => l.adminLiveTvTabRecordings,
      anchor: 'live-tv.RecordingPostProcessorArguments',
    ),
    'library-edit': _Save(
      'POST',
      '/Library/VirtualFolders/LibraryOptions',
      tab: (l) => l.adminLibraryTabOptions,
    ),
    'metadata-edit': const _Save('POST', '/Items/{item}', text: true),
    'user-edit': const _Save('POST', '/Users', text: true),
    'user-policy': _Save(
      'POST',
      '/Users/{user}/Policy',
      page: 'user-edit',
      tab: (l) => l.permissions,
    ),
  };

  // IndexedStack keeps every tab built, so only the shown one counts.
  bool onShownTab(Element e) {
    var shown = true;
    e.visitAncestorElements((a) {
      final w = a.widget;
      if (w is Visibility && !w.visible) shown = false;
      return shown;
    });
    return shown;
  }

  for (final entry in draftPages.entries) {
    testWidgets('${entry.key} saves through the bar', skip: skip != null, (
      tester,
    ) async {
      final spec = entry.value;
      currentPage = '${entry.key}:save';
      await pumpAdmin(tester, pages[spec.page ?? entry.key]!());
      await settle(tester);
      if (spec.tab != null) {
        await tester.tap(find.text(spec.tab!(l10n)));
        await settle(tester);
      }
      final anchor = find.byWidgetPredicate(
        (w) => w is AdminSettingAnchor && w.id == spec.anchor,
      );

      String? original;
      Future<void> changeAndSave({required bool restore}) async {
        Iterable<Element> shown(Type kind) => (spec.anchor == null
                ? find.byType(kind)
                : find.descendant(of: anchor, matching: find.byType(kind)))
            .evaluate()
            .where(onShownTab);
        // Pages without a switch edit their first text field.
        final switches = spec.text ? const <Element>[] : shown(Switch);
        final kind = switches.isEmpty ? TextFormField : Switch;
        final control =
            (switches.isEmpty ? shown(TextFormField) : switches).first.widget;
        final target = find.byWidget(control);
        await tester.ensureVisible(target);
        if (kind == Switch) {
          await tester.tap(target);
        } else {
          final text = tester
              .widget<TextField>(
                find.descendant(of: target, matching: find.byType(TextField)),
              )
              .controller!
              .text;
          original ??= text;
          await tester.enterText(target, restore ? original! : '${text}1');
        }
        await tester.pump();
        expect(AdminDraft.active.value?.isDirty, isTrue);
        // The bar slides in and the last save's snackbar slides out. This
        // binding only draws frames when the test pumps, so pump several.
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        final save = find.widgetWithText(FilledButton, l10n.save);
        await tester.tap(save);
        await settle(tester);
        expect(AdminDraft.active.value?.isDirty, isFalse);
      }

      final before = log.length;
      await changeAndSave(restore: false);
      final method = spec.method;
      final path = spec.path.replaceAllMapped(
        RegExp(r'\{(\w+)\}'),
        (m) => ids[m[1]]!,
      );
      expect(
        log.skip(before).where(
          (r) =>
              r.method == method &&
              r.path == path &&
              (r.status == 204 || r.status == 200),
        ),
        isNotEmpty,
        reason: '${entry.key} should $method $path',
      );
      // Put the server back as it was.
      await changeAndSave(restore: true);
      expectNoFailures(currentPage);
      AdminDraft.active.value = null;
    });
  }
}

/// One page's save check. [tab] opens that tab first, [anchor] picks the
/// search anchor whose field gets edited, and `{id}` names in [path] are
/// filled from the test's ids.
class _Save {
  const _Save(
    this.method,
    this.path, {
    this.page,
    this.tab,
    this.anchor,
    this.text = false,
  });

  final String method;
  final String path;
  final String? page;
  final String Function(AppLocalizations)? tab;
  final String? anchor;
  final bool text;
}
