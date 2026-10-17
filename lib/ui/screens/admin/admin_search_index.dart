import '../../../l10n/app_localizations.dart';
import 'admin_nav.dart';
import 'search/library_search_entries.dart';
import 'search/livetv_search_entries.dart';
import 'search/overview_search_entries.dart';
import 'search/playback_search_entries.dart';
import 'search/system_search_entries.dart';

/// One thing the admin search can find: a page, or a setting on a page.
class AdminSearchEntry {
  const AdminSearchEntry({
    required this.pageId,
    required this.label,
    this.section,
    this.anchor,
  });

  final String pageId;
  final String Function(AppLocalizations l10n) label;
  final String Function(AppLocalizations l10n)? section;

  /// The [AdminSettingAnchor] id of the row, null for a whole page.
  final String? anchor;

  String where(AppLocalizations l10n) {
    final page = adminPageById(pageId);
    final parts = [
      if (page != null) adminGroupOf(page).title(l10n),
      if (page != null) page.title(l10n),
      if (section != null) section!(l10n),
    ];
    return parts.join(' · ');
  }
}

/// A settings row on [page]. Its anchor is `<page>.<key>`, the id the page
/// gives the row's AdminSettingAnchor.
AdminSearchEntry adminSettingRow(
  String page,
  String key,
  String Function(AppLocalizations l10n) label,
  String Function(AppLocalizations l10n) section,
) => AdminSearchEntry(
  pageId: page,
  label: label,
  section: section,
  anchor: '$page.$key',
);

/// Every page, then the settings rows, one file per group under search/.
/// Keep the anchor ids in step with the pages.
List<AdminSearchEntry> adminSearchEntries() => [
  for (final group in adminGroups)
    for (final page in group.pages)
      AdminSearchEntry(pageId: page.id, label: page.title),
  ...overviewSearchEntries,
  ...librarySearchEntries,
  ...livetvSearchEntries,
  ...playbackSearchEntries,
  ...systemSearchEntries,
];

/// Every word of [query] has to appear in the label or where it lives.
List<AdminSearchEntry> matchAdminSearch(
  List<AdminSearchEntry> entries,
  String query,
  AppLocalizations l10n,
) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final matches = <AdminSearchEntry>[];
  for (final entry in entries) {
    final page = adminPageById(entry.pageId);
    final text = [
      entry.label(l10n),
      entry.where(l10n),
      if (entry.anchor == null && page != null) page.description(l10n),
    ].join(' ').toLowerCase();
    if (words.every(text.contains)) matches.add(entry);
  }
  return matches.take(30).toList();
}
