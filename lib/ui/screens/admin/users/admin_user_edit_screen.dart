import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:server_core/server_core.dart';

import '../../../navigation/destinations.dart';
import '../../../widgets/adaptive/adaptive_dialog.dart';
import '../../detail/modern/widgets/details_tab_bar.dart';
import '../admin_draft.dart';
import '../widgets/admin_form_styles.dart';
import '../providers/admin_user_providers.dart';
import 'admin_user_delete_dialog.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../../../../util/platform_detection.dart';

typedef _RatingOption = ({String name, int score, int? subScore});

/// One user's profile, permissions, access, parental control and password.
/// The UserDto and its Policy are one draft with two targets, saved by the
/// shell's bar. Password set and reset act at once.
class AdminUserEditScreen extends ConsumerStatefulWidget {
  final String userId;
  const AdminUserEditScreen({super.key, required this.userId});

  @override
  ConsumerState<AdminUserEditScreen> createState() =>
      _AdminUserEditScreenState();
}

class _AdminUserEditScreenState extends ConsumerState<AdminUserEditScreen>
    with AdminDraftHost {
  int _selectedTab = 0;
  final _tabFocusNodes = <int, FocusNode>{};
  late final MediaServerClient _client;

  /// The UserDto as fetched, minus Policy, which [_policy] edits.
  late Map<String, dynamic> _profile;
  late Map<String, dynamic> _policy;
  List<VirtualFolderInfo> _libraries = const [];
  List<Map<String, dynamic>> _channels = const [];
  List<Map<String, dynamic>> _deletableChannels = const [];
  List<_RatingOption> _ratings = const [];
  List<Map<String, dynamic>> _authProviders = const [];
  List<Map<String, dynamic>> _resetProviders = const [];
  List<DeviceInfoDto> _devices = const [];
  bool _serverRemoteAccess = true;

  final _currentPasswordController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _tagControllers = <String, TextEditingController>{};

  bool _loading = true;
  bool _passwordBusy = false;
  String? _error;

  /// Set on every build, for the draft's posts, which may finish after the
  /// page has gone.
  late AppLocalizations _l10n;

  AdminUsersApi get _users => _client.adminUsersApi;

  @override
  void initState() {
    super.initState();
    _client = GetIt.instance<MediaServerClient>();
    _load();
  }

  FocusNode _tabNode(int index) {
    return _tabFocusNodes.putIfAbsent(
        index, () => FocusNode(debugLabel: 'admin_user_tab_$index'));
  }

  @override
  void dispose() {
    for (final node in _tabFocusNodes.values) {
      node.dispose();
    }
    _currentPasswordController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    for (final c in _tagControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> _fetchUser() async =>
      Map<String, dynamic>.of((await _users.getUserById(widget.userId)).raw);

  // A missing Policy throws, so a partial policy is never posted.
  Future<Map<String, dynamic>> _fetchPolicy() async =>
      Map<String, dynamic>.from((await _fetchUser())['Policy'] as Map);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Reference lists are optional, so a failed one is empty instead of
      // failing the whole screen. They load alongside the user.
      Future<List<Map<String, dynamic>>> list(
        Future<List<Map<String, dynamic>>> call,
      ) => call.catchError((_) => <Map<String, dynamic>>[]);
      final ratingsLoad = list(_client.adminSystemApi.getParentalRatings());
      final authLoad = list(_client.adminSystemApi.getAuthProviders());
      final resetLoad =
          list(_client.adminSystemApi.getPasswordResetProviders());
      final channelsLoad = list(_users.getChannels());
      final deletableLoad =
          list(_users.getChannels(supportsMediaDeletion: true));
      final devicesLoad = _client.adminDevicesApi
          .getDevices()
          .catchError((_) => <DeviceInfoDto>[]);
      final networkLoad = _client.adminSystemApi
          .getNamedConfiguration('network')
          .catchError((_) => <String, dynamic>{});
      final user = await _fetchUser();
      final libraries = await _client.adminLibraryApi.getMediaFolders(
        isHidden: false,
      );
      final ratings = await ratingsLoad;
      final authProviders = await authLoad;
      final resetProviders = await resetLoad;
      final channels = await channelsLoad;
      final deletable = await deletableLoad;
      final devices = await devicesLoad;
      final network = await networkLoad;
      if (!mounted) return;
      final policy = Map<String, dynamic>.from(user['Policy'] as Map);
      final profile = user..remove('Policy');
      setState(() {
        _profile = profile;
        _policy = policy;
        _libraries = libraries;
        _ratings = _groupRatings(ratings);
        _authProviders = authProviders;
        _resetProviders = resetProviders;
        _channels = channels;
        _deletableChannels = deletable;
        _devices = devices;
        _serverRemoteAccess = network['EnableRemoteAccess'] != false;
        _loading = false;
      });
      hostDraft(AdminDraft({
        // The whole UserDto goes back, so the user's Configuration survives a
        // rename.
        'profile': AdminDraftTarget(
          working: profile,
          reload: _fetchUser,
          post: (dto) async {
            final name = '${dto['Name'] ?? ''}'.trim();
            if (name.isEmpty) throw Exception(_l10n.adminUsernameRequired);
            await _users.updateUser(widget.userId, {...dto, 'Name': name});
            if (mounted) ref.invalidate(adminUsersListProvider);
          },
        ),
        'policy': AdminDraftTarget(
          working: policy,
          reload: _fetchPolicy,
          post: (value) async {
            if (_badSchedule(value) != null) {
              throw Exception(_l10n.adminScheduleStartBeforeEnd);
            }
            await _users.updateUserPolicy(widget.userId, value);
            if (mounted) ref.invalidate(adminUsersListProvider);
          },
        ),
      }));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e, AppLocalizations.of(context));
        _loading = false;
      });
    }
  }

  void _editPolicy(void Function(Map<String, dynamic> policy) change) {
    setState(() => change(_policy));
    edited();
  }

  /// Null removes the key, so clearing a nullable value the server left out
  /// doesn't count as an edit.
  void _setPolicy(String key, Object? value) => _editPolicy((p) {
        if (value == null) {
          p.remove(key);
        } else {
          p[key] = value;
        }
      });

  List<String> _listOf(String key) =>
      List<String>.from(_policy[key] as List? ?? const []);

  void _toggleListMembership(String key, String value, bool enabled) {
    final list = _listOf(key)..remove(value);
    if (enabled) list.add(value);
    _setPolicy(key, list);
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Future<void> _savePassword() async {
    final l10n = AppLocalizations.of(context);
    final pw = _passwordController.text;
    if (pw != _confirmPasswordController.text) {
      _snack(l10n.adminPasswordsMismatch);
      return;
    }
    // An administrator can't be left without a password.
    if (pw.isEmpty && _isAdmin) {
      _snack(l10n.adminNewPasswordEmpty);
      return;
    }
    await _passwordAction(
      () => _users.updateUserPassword(
        widget.userId,
        currentPassword: _isSelf ? _currentPasswordController.text : null,
        newPassword: pw,
      ),
      l10n.adminPasswordUpdated,
    );
  }

  Future<void> _resetPassword() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(l10n.adminResetPassword),
        content: Text(l10n.adminResetPasswordWarning),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.reset),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _passwordAction(
      () => _users.updateUserPassword(widget.userId, resetPassword: true),
      l10n.adminPasswordReset,
    );
  }

  Future<void> _passwordAction(
    Future<void> Function() call,
    String done,
  ) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _passwordBusy = true);
    try {
      await call();
      if (!mounted) return;
      _currentPasswordController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      _snack(done);
    } catch (e) {
      if (mounted) _snack(l10n.adminFailed(describeError(e, l10n)));
    } finally {
      if (mounted) setState(() => _passwordBusy = false);
    }
  }

  bool get _isSelf => _client.userId == widget.userId;
  bool get _isAdmin => _policy['IsAdministrator'] == true;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.adminUserLoadFailed,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _load, child: Text(l10n.retry)),
          ],
        ),
      );
    }

    final name = '${_profile['Name'] ?? ''}'.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: adminScreenHeader(
            context,
            title: name.isEmpty ? l10n.adminUserSettings : name,
            icon: Icons.person_outline,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: DetailsTabBar(
            segmented: true,
            wrap: PlatformDetection.useMobileUi,
            labels: [
              l10n.profile,
              l10n.permissions,
              l10n.access,
              l10n.adminParentalControl,
              l10n.password,
            ],
            selectedIndex: _selectedTab,
            onSelect: (i) => setState(() => _selectedTab = i),
            focusNodeFor: _tabNode,
          ),
        ),
        Expanded(
          child: draftKeyed(
            IndexedStack(
              index: _selectedTab,
              children: [
                _tab(_buildProfileTab(l10n)),
                _tab(_buildPermissionsTab(l10n)),
                _tab(_buildAccessTab(l10n)),
                _tab(_buildParentalTab(l10n)),
                _tab(_buildPasswordTab(l10n)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tab(List<Widget> children) => ListView(
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, MediaQuery.of(context).padding.bottom + 40),
        children: children,
      );

  List<Widget> _buildProfileTab(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return [
      if (_policy['IsDisabled'] == true)
        Card(
          color: scheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              l10n.adminUserDisabledBanner,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ),
      adminSection(
        context,
        title: l10n.profile,
        icon: Icons.badge_outlined,
        children: [
          adminFieldRow(
            label: l10n.username,
            child: TextFormField(
              initialValue: '${_profile['Name'] ?? ''}',
              decoration: adminInputDecoration(),
              onChanged: (v) {
                setState(() => _profile['Name'] = v);
                edited();
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => showAdminUserDeleteDialog(
            context,
            user: ServerUser(id: widget.userId, name: '${_profile['Name']}'),
            onDeleted: () {
              ref.invalidate(adminUsersListProvider);
              draft?.discard();
              context.go(Destinations.adminUsers);
            },
          ),
          icon: const Icon(Icons.delete),
          label: Text(l10n.adminDeleteUser),
          style: TextButton.styleFrom(foregroundColor: scheme.error),
        ),
      ),
    ];
  }

  List<Widget> _buildPermissionsTab(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return [
      adminSection(
        context,
        title: l10n.admin,
        icon: Icons.shield_outlined,
        children: [
          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                l10n.adminFullAccessWarning,
                style: TextStyle(color: scheme.error),
              ),
            ),
          _policySwitch('IsAdministrator', l10n.administrator),
          _policySwitch('IsHidden', l10n.adminHiddenUser),
          _policySwitch('IsDisabled', l10n.disabled),
        ],
      ),
      adminSection(
        context,
        title: l10n.playback,
        icon: Icons.play_circle_outline,
        children: [
          _policySwitch('EnableMediaPlayback', l10n.adminAllowMediaPlayback),
          _policySwitch(
              'EnableAudioPlaybackTranscoding', l10n.adminAllowAudioTranscoding),
          _policySwitch(
              'EnableVideoPlaybackTranscoding', l10n.adminAllowVideoTranscoding),
          _policySwitch('EnablePlaybackRemuxing', l10n.adminAllowRemuxing),
          _policySwitch(
              'ForceRemoteSourceTranscoding', l10n.adminForceRemoteTranscoding),
          adminFieldRow(
            label: l10n.adminRemoteBitrateLimitMbps,
            helper: l10n.adminLeaveEmptyNoLimit,
            child: TextFormField(
              initialValue: _mbps(_policy['RemoteClientBitrateLimit']),
              decoration: adminInputDecoration(),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              // Stored in bits per second, empty is 0 (no limit).
              onChanged: (v) => _setPolicy('RemoteClientBitrateLimit',
                  ((double.tryParse(v.trim()) ?? 0) * 1e6).floor()),
            ),
          ),
        ],
      ),
      adminSection(
        context,
        title: l10n.content,
        icon: Icons.folder_outlined,
        children: [
          _policySwitch(
              'EnableContentDownloading', l10n.adminAllowContentDownloading),
          _policySwitch('EnablePublicSharing', l10n.adminAllowPublicSharing),
        ],
      ),
      adminSection(
        context,
        title: l10n.sessions,
        icon: Icons.devices_outlined,
        children: [
          _policySwitch(
              'EnableRemoteControlOfOtherUsers', l10n.adminAllowRemoteControl),
          _policySwitch(
              'EnableSharedDeviceControl', l10n.adminAllowSharedDeviceControl),
          if (_serverRemoteAccess)
            _policySwitch('EnableRemoteAccess', l10n.adminAllowRemoteAccess),
          _intField('MaxActiveSessions', l10n.adminMaxActiveSessions,
              l10n.adminLeaveEmptyNoLimit),
        ],
      ),
      adminSection(
        context,
        title: l10n.features,
        icon: Icons.tune,
        children: [
          _policySwitch('EnableLiveTvAccess', l10n.adminAllowLiveTvAccess),
          _policySwitch(
              'EnableLiveTvManagement', l10n.adminAllowLiveTvManagement),
          _policySwitch(
              'EnableCollectionManagement', l10n.adminAllowCollectionManagement),
          _policySwitch(
              'EnableSubtitleManagement', l10n.adminAllowSubtitleManagement),
          _policySwitch('EnableLyricManagement', l10n.adminAllowLyricManagement),
        ],
      ),
      adminSection(
        context,
        title: l10n.authentication,
        icon: Icons.lock_outline,
        children: [
          if (_authProviders.length > 1)
            _providerDropdown(
              label: l10n.adminAuthProvider,
              policyKey: 'AuthenticationProviderId',
              providers: _authProviders,
            ),
          if (_resetProviders.length > 1)
            _providerDropdown(
              label: l10n.adminPasswordResetProvider,
              policyKey: 'PasswordResetProviderId',
              providers: _resetProviders,
            ),
          _intField('LoginAttemptsBeforeLockout',
              l10n.adminLoginAttemptsBeforeLockout, l10n.adminLoginAttemptsHint),
          adminFieldRow(
            label: l10n.adminSyncPlayAccess,
            child: DropdownButtonFormField<String>(
              initialValue:
                  (_policy['SyncPlayAccess'] as String?) ?? 'CreateAndJoinGroups',
              isExpanded: true,
              decoration: adminInputDecoration(),
              items: [
                DropdownMenuItem(
                  value: 'CreateAndJoinGroups',
                  child: Text(l10n.adminSyncPlayCreateAndJoin),
                ),
                DropdownMenuItem(
                  value: 'JoinGroups',
                  child: Text(l10n.adminSyncPlayJoin),
                ),
                DropdownMenuItem(
                  value: 'None',
                  child: Text(l10n.adminSyncPlayNone),
                ),
              ],
              onChanged: (v) => _setPolicy('SyncPlayAccess', v),
            ),
          ),
        ],
      ),
    ];
  }

  static String _mbps(Object? bps) {
    if (bps is! num || bps <= 0) return '';
    final mbps = bps / 1e6;
    return mbps == mbps.roundToDouble()
        ? mbps.toInt().toString()
        : mbps.toString();
  }

  /// The server's ints aren't nullable, so an empty field is 0.
  Widget _intField(String key, String label, String helper) {
    return adminFieldRow(
      label: label,
      helper: helper,
      child: TextFormField(
        initialValue: '${_policy[key] ?? ''}',
        decoration: adminInputDecoration(),
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        onChanged: (v) => _setPolicy(key, int.tryParse(v.trim()) ?? 0),
      ),
    );
  }

  Widget _providerDropdown({
    required String label,
    required String policyKey,
    required List<Map<String, dynamic>> providers,
  }) {
    final current = _policy[policyKey] as String?;
    final ids = providers
        .map((p) => (p['Id'] ?? p['id'])?.toString())
        .whereType<String>()
        .toList();
    return adminFieldRow(
      label: label,
      child: DropdownButtonFormField<String>(
        initialValue: ids.contains(current)
            ? current
            : (ids.isNotEmpty ? ids.first : null),
        isExpanded: true,
        decoration: adminInputDecoration(),
        items: providers.map((p) {
          final id = (p['Id'] ?? p['id'])?.toString() ?? '';
          final name = (p['Name'] ?? p['name'])?.toString() ?? id;
          return DropdownMenuItem(value: id, child: Text(name));
        }).toList(),
        onChanged: (v) => _setPolicy(policyKey, v),
      ),
    );
  }

  List<Widget> _buildAccessTab(AppLocalizations l10n) {
    String nameOf(Map<String, dynamic> item) => '${item['Name'] ?? item['Id']}';
    return [
      adminSection(
        context,
        title: l10n.adminLibraryAccess,
        icon: Icons.video_library_outlined,
        children: _allOrSome(
          'EnableAllFolders',
          'EnabledFolders',
          l10n.adminEnableAllLibraryAccess,
          [for (final lib in _libraries) (lib.itemId, lib.name)],
        ),
      ),
      if (_channels.isNotEmpty)
        adminSection(
          context,
          title: l10n.adminChannelAccess,
          icon: Icons.live_tv_outlined,
          children: _allOrSome(
            'EnableAllChannels',
            'EnabledChannels',
            l10n.adminEnableAllChannels,
            [for (final c in _channels) ('${c['Id']}', nameOf(c))],
          ),
        ),
      // Administrators sign in from any device, so this is hidden for them.
      if (!_isAdmin)
        adminSection(
          context,
          title: l10n.adminDeviceAccess,
          icon: Icons.devices_outlined,
          children: _allOrSome(
            'EnableAllDevices',
            'EnabledDevices',
            l10n.adminEnableAllDevices,
            [for (final d in _devices) (d.id, _deviceLabel(d))],
          ),
        ),
      adminSection(
        context,
        title: l10n.adminContentDeletionFolders,
        icon: Icons.delete_outline,
        children: _allOrSome(
          'EnableContentDeletion',
          'EnableContentDeletionFromFolders',
          l10n.adminDeleteFromAllLibraries,
          [
            for (final lib in _libraries) (lib.itemId, lib.name),
            for (final c in _deletableChannels) ('${c['Id']}', nameOf(c)),
          ],
        ),
      ),
    ];
  }

  /// `CustomName or Name - AppName`, else the device id.
  static String _deviceLabel(DeviceInfoDto d) {
    final label = [
      d.customName?.isNotEmpty == true ? d.customName : d.name,
      d.appName,
    ].whereType<String>().join(' - ');
    return label.isEmpty ? d.id : label;
  }

  /// An "all" switch and, while it's off, one checkbox per item. Turning it
  /// on empties the list.
  List<Widget> _allOrSome(
    String allKey,
    String listKey,
    String allLabel,
    List<(String, String)> items,
  ) {
    final all = _policy[allKey] == true;
    final selected = _listOf(listKey);
    return [
      adminSwitchRow(
        title: allLabel,
        value: all,
        onChanged: (v) => _editPolicy((p) {
          p[allKey] = v;
          if (v) p[listKey] = <String>[];
        }),
      ),
      if (!all)
        for (final (id, name) in items)
          CheckboxListTile(
            title: Text(name),
            value: selected.contains(id),
            onChanged: (v) => _toggleListMembership(listKey, id, v ?? false),
          ),
    ];
  }

  /// Neighbouring ratings with the same score and sub score are one option,
  /// their names joined with "/".
  static List<_RatingOption> _groupRatings(List<Map<String, dynamic>> raw) {
    final out = <_RatingOption>[];
    for (final r in raw) {
      final name = r['Name']?.toString();
      final ratingScore = r['RatingScore'];
      // Servers before RatingScore only send Value.
      final score = ratingScore is Map
          ? ratingScore['score'] as int?
          : r['Value'] as int?;
      final subScore = ratingScore is Map ? ratingScore['subScore'] as int? : null;
      if (name == null || score == null) continue;
      if (out.isNotEmpty &&
          out.last.score == score &&
          out.last.subScore == subScore) {
        out.last = (
          name: '${out.last.name}/$name',
          score: score,
          subScore: subScore,
        );
      } else {
        out.add((name: name, score: score, subScore: subScore));
      }
    }
    return out;
  }

  /// The exact score and sub score, else the highest score at or below it.
  int? _ratingIndex() {
    final max = _policy['MaxParentalRating'] as int?;
    if (max == null) return null;
    final sub = _policy['MaxParentalSubRating'] as int?;
    final exact = _ratings.lastIndexWhere(
        (o) => o.score == max && o.subScore == sub);
    if (exact != -1) return exact;
    final below = _ratings.lastIndexWhere((o) => o.score <= max);
    return below == -1 ? null : below;
  }

  List<Widget> _buildParentalTab(AppLocalizations l10n) {
    final unratedItems = <(String, String)>[
      ('Book', l10n.adminUnratedBook),
      ('ChannelContent', l10n.adminUnratedChannelContent),
      ('LiveTvChannel', l10n.adminUnratedLiveTvChannel),
      ('Movie', l10n.adminUnratedMovie),
      ('Music', l10n.adminUnratedMusic),
      ('Trailer', l10n.adminUnratedTrailer),
      ('Series', l10n.adminUnratedSeries),
    ];
    final blocked = _listOf('BlockUnratedItems');

    return [
      adminSection(
        context,
        title: l10n.adminMaxParentalRating,
        icon: Icons.family_restroom,
        children: [
          adminFieldRow(
            label: l10n.adminMaxParentalRating,
            helper: l10n.adminMaxParentalRatingHint,
            child: DropdownButtonFormField<int?>(
              initialValue: _ratingIndex(),
              isExpanded: true,
              decoration: adminInputDecoration(),
              items: [
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text(l10n.adminParentalRatingNone),
                ),
                for (var i = 0; i < _ratings.length; i++)
                  DropdownMenuItem<int?>(value: i, child: Text(_ratings[i].name)),
              ],
              onChanged: (i) => _editPolicy((p) {
                p.remove('MaxParentalRating');
                p.remove('MaxParentalSubRating');
                if (i == null) return;
                p['MaxParentalRating'] = _ratings[i].score;
                if (_ratings[i].subScore != null) {
                  p['MaxParentalSubRating'] = _ratings[i].subScore;
                }
              }),
            ),
          ),
        ],
      ),
      adminSection(
        context,
        title: l10n.adminBlockUnratedItems,
        icon: Icons.block,
        children: [
          for (final (value, label) in unratedItems)
            CheckboxListTile(
              title: Text(label),
              value: blocked.contains(value),
              onChanged: (v) =>
                  _toggleListMembership('BlockUnratedItems', value, v ?? false),
            ),
        ],
      ),
      adminSection(
        context,
        title: l10n.adminAllowedTags,
        icon: Icons.label_outline,
        children: [_buildTagEditor('AllowedTags', l10n.adminAllowedTagsHint, l10n)],
      ),
      adminSection(
        context,
        title: l10n.adminBlockedTags,
        icon: Icons.label_off_outlined,
        children: [_buildTagEditor('BlockedTags', l10n.adminBlockedTagsHint, l10n)],
      ),
      if (!_isAdmin)
        adminSection(
          context,
          title: l10n.adminAccessSchedules,
          icon: Icons.schedule,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(l10n.adminAccessSchedulesHint,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            ..._buildSchedules(l10n),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _setPolicy('AccessSchedules', [
                    ..._schedules,
                    {'DayOfWeek': 'Everyday', 'StartHour': 0, 'EndHour': 24},
                  ]),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.adminAddSchedule),
                ),
              ),
            ),
          ],
        ),
    ];
  }

  static const List<String> _dayValues = [
    'Everyday',
    'Weekday',
    'Weekend',
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  String _dayLabel(String value, AppLocalizations l10n) {
    switch (value) {
      case 'Everyday':
        return l10n.adminDayEveryday;
      case 'Weekday':
        return l10n.adminDayWeekday;
      case 'Weekend':
        return l10n.adminDayWeekend;
      case 'Sunday':
        return l10n.adminDaySunday;
      case 'Monday':
        return l10n.adminDayMonday;
      case 'Tuesday':
        return l10n.adminDayTuesday;
      case 'Wednesday':
        return l10n.adminDayWednesday;
      case 'Thursday':
        return l10n.adminDayThursday;
      case 'Friday':
        return l10n.adminDayFriday;
      case 'Saturday':
        return l10n.adminDaySaturday;
    }
    return value;
  }

  List<Map<String, dynamic>> get _schedules => [
        for (final s in _policy['AccessSchedules'] as List? ?? const [])
          Map<String, dynamic>.from(s as Map),
      ];

  /// The index of the first schedule whose start isn't before its end.
  static int? _badSchedule(Map<String, dynamic> policy) {
    final schedules = policy['AccessSchedules'] as List? ?? const [];
    for (var i = 0; i < schedules.length; i++) {
      final s = schedules[i] as Map;
      if (((s['StartHour'] as num?) ?? 0) >= ((s['EndHour'] as num?) ?? 0)) {
        return i;
      }
    }
    return null;
  }

  List<Widget> _buildSchedules(AppLocalizations l10n) {
    final schedules = _schedules;
    final bad = _badSchedule(_policy);
    return [
      for (var i = 0; i < schedules.length; i++)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  initialValue: _dayValues.contains(schedules[i]['DayOfWeek'])
                      ? schedules[i]['DayOfWeek'] as String
                      : 'Everyday',
                  isExpanded: true,
                  decoration: adminInputDecoration(label: l10n.adminScheduleDay),
                  items: _dayValues
                      .map((d) => DropdownMenuItem(
                          value: d, child: Text(_dayLabel(d, l10n))))
                      .toList(),
                  onChanged: (v) => _updateSchedule(i, 'DayOfWeek', v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _hourDropdown(l10n.adminScheduleStart,
                    schedules[i]['StartHour'], null,
                    (v) => _updateSchedule(i, 'StartHour', v)),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _hourDropdown(l10n.adminScheduleEnd,
                    schedules[i]['EndHour'],
                    i == bad ? l10n.adminScheduleStartBeforeEnd : null,
                    (v) => _updateSchedule(i, 'EndHour', v)),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    _setPolicy('AccessSchedules', schedules..removeAt(i)),
              ),
            ],
          ),
        ),
    ];
  }

  /// Half hours from 0:00 to 24:00, plus the stored value when it's off that
  /// grid.
  Widget _hourDropdown(
    String label,
    Object? raw,
    String? error,
    ValueChanged<double?> onChanged,
  ) {
    final value = (raw as num? ?? 0).toDouble();
    final hours = {for (var i = 0; i <= 48; i++) i / 2, value}.toList()..sort();
    String text(double h) =>
        '${h.floor().toString().padLeft(2, '0')}:'
        '${((h % 1) * 60).round().toString().padLeft(2, '0')}';
    return DropdownButtonFormField<double>(
      initialValue: value,
      isExpanded: true,
      decoration: adminInputDecoration(label: label)
          .copyWith(errorText: error, errorMaxLines: 3),
      items: [
        for (final h in hours) DropdownMenuItem(value: h, child: Text(text(h))),
      ],
      onChanged: onChanged,
    );
  }

  void _updateSchedule(int index, String key, Object? value) {
    if (value == null) return;
    final schedules = _schedules;
    schedules[index][key] = value;
    _setPolicy('AccessSchedules', schedules);
  }

  Widget _buildTagEditor(String key, String hint, AppLocalizations l10n) {
    final tags = _listOf(key);
    final controller =
        _tagControllers.putIfAbsent(key, () => TextEditingController());
    void addTag() {
      final t = controller.text.trim();
      if (t.isEmpty) return;
      if (!tags.contains(t)) _setPolicy(key, [...tags, t]);
      controller.clear();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (tags.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in tags)
                  Chip(
                    label: Text(t),
                    onDeleted: () =>
                        _setPolicy(key, tags.where((x) => x != t).toList()),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: adminInputDecoration(hint: l10n.adminAddTag),
                  onSubmitted: (_) => addTag(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: l10n.adminAddTag,
                onPressed: addTag,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPasswordTab(AppLocalizations l10n) {
    Widget field(String label, TextEditingController controller) =>
        adminFieldRow(
          label: label,
          child: TextField(
            controller: controller,
            decoration: adminInputDecoration(),
            obscureText: true,
          ),
        );
    return [
      adminSection(
        context,
        title: l10n.adminChangePassword,
        icon: Icons.password,
        children: [
          // The server checks it when an admin changes their own password.
          if (_isSelf) field(l10n.adminCurrentPassword, _currentPasswordController),
          field(l10n.adminNewPassword, _passwordController),
          field(l10n.adminConfirmPassword, _confirmPasswordController),
        ],
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: _passwordBusy ? null : _savePassword,
            child: Text(l10n.adminSetPassword),
          ),
          // A reset removes the password, and an administrator can't be left
          // without one.
          if (!_isAdmin)
            OutlinedButton(
              onPressed: _passwordBusy ? null : _resetPassword,
              child: Text(l10n.adminResetPassword),
            ),
        ],
      ),
    ];
  }

  Widget _policySwitch(String key, String label) {
    return adminSwitchRow(
      title: label,
      value: _policy[key] as bool? ?? false,
      onChanged: (v) => _setPolicy(key, v),
    );
  }
}
