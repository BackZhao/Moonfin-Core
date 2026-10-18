import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/viewmodels/book_browse_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/focus/dpad_keys.dart';
import '../focus/glass_focus_halo.dart';
import 'book_segmented_control.dart';

/// The format filter for mixed libraries, drawn as the same pill as the
/// Library/Discover tabs. The whole pill is one focus stop, and left and right
/// move the selection while it's focused.
class BookScopeFilter extends StatefulWidget {
  final BookScope value;
  final ValueChanged<BookScope> onChanged;
  final List<BookScope>? availableScopes;
  final FocusNode? focusNode;

  /// Up and down D-pad presses from the pill. Returns true when handled.
  final bool Function(bool isUp)? onVerticalNavigation;

  const BookScopeFilter({
    super.key,
    required this.value,
    required this.onChanged,
    this.availableScopes,
    this.focusNode,
    this.onVerticalNavigation,
  });

  @override
  State<BookScopeFilter> createState() => _BookScopeFilterState();
}

class _BookScopeFilterState extends State<BookScopeFilter> {
  List<BookScope> get _scopes => widget.availableScopes ?? BookScope.values;

  FocusNode? _ownedNode;
  FocusNode get _node =>
      widget.focusNode ?? (_ownedNode ??= FocusNode(debugLabel: 'BookScopeFilter'));

  bool _focused = false;

  @override
  void dispose() {
    _ownedNode?.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final scopes = _scopes;
    final index = scopes.indexOf(widget.value);
    if (key.isLeftKey) {
      if (index > 0) widget.onChanged(scopes[index - 1]);
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      if (index >= 0 && index < scopes.length - 1) {
        widget.onChanged(scopes[index + 1]);
      }
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && (key.isUpKey || key.isDownKey)) {
      final handled = widget.onVerticalNavigation?.call(key.isUpKey) ?? false;
      return handled ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scopes = _scopes;
    final selectedIndex = scopes.indexOf(widget.value);

    return Focus(
      focusNode: _node,
      onKeyEvent: _onKeyEvent,
      onFocusChange: (has) => setState(() => _focused = has),
      child: GlassFocusHalo(
        focused: _focused,
        scale: 1.0,
        borderRadius: BorderRadius.circular(999),
        child: BookSegmentedControl(
          labels: [for (final scope in scopes) bookScopeLabel(l10n, scope)],
          selectedIndex: selectedIndex >= 0 ? selectedIndex : 0,
          onChanged: (i) => widget.onChanged(scopes[i]),
        ),
      ),
    );
  }
}

String bookScopeLabel(AppLocalizations l10n, BookScope scope) =>
    switch (scope) {
      BookScope.all => l10n.all,
      BookScope.books => l10n.books,
      BookScope.audiobooks => l10n.audiobooks,
      BookScope.comics => l10n.comics,
    };
