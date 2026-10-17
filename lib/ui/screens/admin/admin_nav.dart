import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../navigation/destinations.dart';

/// One page of the admin area, as the rail, page list and phone tabs show it.
class AdminPage {
  const AdminPage({
    required this.id,
    required this.route,
    required this.icon,
    required this.title,
    required this.description,
    this.iconAsset,
  });

  final String id;
  final String route;
  final IconData icon;

  /// A tinted image in place of [icon] (Libraries uses the clapperboard).
  final String? iconAsset;
  final String Function(AppLocalizations l10n) title;
  final String Function(AppLocalizations l10n) description;

  Widget buildIcon(double size, Color color) => iconAsset == null
      ? Icon(icon, size: size, color: color)
      : Image.asset(iconAsset!, width: size, height: size, color: color);
}

class AdminGroup {
  const AdminGroup({
    required this.id,
    required this.icon,
    required this.title,
    required this.pages,
  });

  final String id;
  final IconData icon;
  final String Function(AppLocalizations l10n) title;
  final List<AdminPage> pages;
}

/// The admin area grouped by task rather than by server subsystem.
final List<AdminGroup> adminGroups = [
  AdminGroup(
    id: 'overview',
    icon: Icons.monitor_heart_outlined,
    title: (l) => l.adminGroupOverview,
    pages: [
      AdminPage(
        id: 'dashboard',
        route: Destinations.admin,
        icon: Icons.dashboard_outlined,
        title: (l) => l.adminDrawerDashboard,
        description: (l) => l.adminPageDescDashboard,
      ),
      AdminPage(
        id: 'analytics',
        route: Destinations.adminAnalytics,
        icon: Icons.insights,
        title: (l) => l.adminDrawerAnalytics,
        description: (l) => l.adminPageDescAnalytics,
      ),
      AdminPage(
        id: 'activity',
        route: Destinations.adminActivity,
        icon: Icons.history,
        title: (l) => l.adminDrawerActivity,
        description: (l) => l.adminPageDescActivity,
      ),
      AdminPage(
        id: 'scheduled-tasks',
        route: Destinations.adminTasks,
        icon: Icons.schedule,
        title: (l) => l.adminDrawerScheduledTasks,
        description: (l) => l.adminPageDescTasks,
      ),
    ],
  ),
  AdminGroup(
    id: 'library',
    icon: Icons.video_library_outlined,
    title: (l) => l.adminGroupLibrary,
    pages: [
      AdminPage(
        id: 'libraries',
        route: Destinations.adminLibraries,
        icon: Icons.movie_outlined,
        iconAsset: 'assets/icons/clapperboard.png',
        title: (l) => l.adminDrawerLibraries,
        description: (l) => l.adminPageDescLibraries,
      ),
      AdminPage(
        id: 'display',
        route: Destinations.adminSettingsDisplay,
        icon: Icons.grid_view,
        title: (l) => l.adminDrawerDisplay,
        description: (l) => l.adminPageDescDisplay,
      ),
      AdminPage(
        id: 'metadata',
        route: Destinations.adminSettingsMetadata,
        icon: Icons.description_outlined,
        title: (l) => l.adminDrawerMetadata,
        description: (l) => l.adminPageDescMetadata,
      ),
      AdminPage(
        id: 'nfo',
        route: Destinations.adminSettingsNfo,
        icon: Icons.text_snippet_outlined,
        title: (l) => l.adminDrawerNfo,
        description: (l) => l.adminPageDescNfo,
      ),
      AdminPage(
        id: 'live-tv',
        route: Destinations.adminLiveTv,
        icon: Icons.live_tv,
        title: (l) => l.adminDrawerLiveTv,
        description: (l) => l.adminPageDescLiveTv,
      ),
    ],
  ),
  AdminGroup(
    id: 'playback',
    icon: Icons.play_circle_outline,
    title: (l) => l.adminGroupPlayback,
    pages: [
      AdminPage(
        id: 'transcoding',
        route: Destinations.adminSettingsPlayback,
        icon: Icons.swap_horiz,
        title: (l) => l.adminDrawerTranscoding,
        description: (l) => l.adminPageDescTranscoding,
      ),
      AdminPage(
        id: 'resume',
        route: Destinations.adminSettingsResume,
        icon: Icons.play_circle_outline,
        title: (l) => l.adminDrawerResume,
        description: (l) => l.adminPageDescResume,
      ),
      AdminPage(
        id: 'streaming',
        route: Destinations.adminSettingsStreaming,
        icon: Icons.stream,
        title: (l) => l.adminDrawerStreaming,
        description: (l) => l.adminPageDescStreaming,
      ),
      AdminPage(
        id: 'trickplay',
        route: Destinations.adminSettingsTrickplay,
        icon: Icons.view_comfy,
        title: (l) => l.adminDrawerTrickplay,
        description: (l) => l.adminPageDescTrickplay,
      ),
    ],
  ),
  AdminGroup(
    id: 'people',
    icon: Icons.group_outlined,
    title: (l) => l.adminGroupPeople,
    pages: [
      AdminPage(
        id: 'users',
        route: Destinations.adminUsers,
        icon: Icons.people_outline,
        title: (l) => l.adminDrawerUsers,
        description: (l) => l.adminPageDescUsers,
      ),
      AdminPage(
        id: 'devices',
        route: Destinations.adminDevices,
        icon: Icons.devices,
        title: (l) => l.adminDrawerDevices,
        description: (l) => l.adminPageDescDevices,
      ),
      AdminPage(
        id: 'api-keys',
        route: Destinations.adminKeys,
        icon: Icons.vpn_key_outlined,
        title: (l) => l.adminDrawerApiKeys,
        description: (l) => l.adminPageDescApiKeys,
      ),
    ],
  ),
  AdminGroup(
    id: 'system',
    icon: Icons.tune,
    title: (l) => l.adminGroupSystem,
    pages: [
      AdminPage(
        id: 'settings',
        route: Destinations.adminSettings,
        icon: Icons.settings_outlined,
        title: (l) => l.adminDrawerSettings,
        description: (l) => l.adminPageDescSettings,
      ),
      AdminPage(
        id: 'branding',
        route: Destinations.adminSettingsBranding,
        icon: Icons.brush_outlined,
        title: (l) => l.adminDrawerBranding,
        description: (l) => l.adminPageDescBranding,
      ),
      AdminPage(
        id: 'networking',
        route: Destinations.adminSettingsNetworking,
        icon: Icons.language,
        title: (l) => l.adminDrawerNetworking,
        description: (l) => l.adminPageDescNetworking,
      ),
      AdminPage(
        id: 'plugins',
        route: Destinations.adminPlugins,
        icon: Icons.extension_outlined,
        title: (l) => l.adminDrawerPlugins,
        description: (l) => l.adminPageDescPlugins,
      ),
      AdminPage(
        id: 'repositories',
        route: Destinations.adminRepositories,
        icon: Icons.source_outlined,
        title: (l) => l.adminDrawerRepositories,
        description: (l) => l.adminPageDescRepositories,
      ),
      AdminPage(
        id: 'backups',
        route: Destinations.adminBackups,
        icon: Icons.backup_outlined,
        title: (l) => l.adminDrawerBackups,
        description: (l) => l.adminPageDescBackups,
      ),
      AdminPage(
        id: 'logs',
        route: Destinations.adminLogs,
        icon: Icons.article_outlined,
        title: (l) => l.adminDrawerLogs,
        description: (l) => l.adminPageDescLogs,
      ),
    ],
  ),
];

/// Sub-routes whose path doesn't start with their page's route.
const _extraPrefixes = {'/admin/metadata': 'libraries'};

/// The page a path belongs to: the longest page route that prefixes it, so
/// `/admin/users/123` is Users and `/admin/settings/playback` is Transcoding.
AdminPage? adminPageFor(String path) {
  AdminPage? best;
  for (final group in adminGroups) {
    for (final page in group.pages) {
      final route = page.route;
      final matches = route == Destinations.admin
          ? path == route
          : path == route || path.startsWith('$route/');
      if (matches && (best == null || route.length > best.route.length)) {
        best = page;
      }
    }
  }
  if (best != null) return best;
  for (final entry in _extraPrefixes.entries) {
    if (path.startsWith(entry.key)) return adminPageById(entry.value);
  }
  return null;
}

AdminPage? adminPageById(String id) {
  for (final group in adminGroups) {
    for (final page in group.pages) {
      if (page.id == id) return page;
    }
  }
  return null;
}

AdminGroup adminGroupOf(AdminPage page) =>
    adminGroups.firstWhere((g) => g.pages.contains(page));

AdminGroup? adminGroupById(String id) {
  for (final group in adminGroups) {
    if (group.id == id) return group;
  }
  return null;
}
