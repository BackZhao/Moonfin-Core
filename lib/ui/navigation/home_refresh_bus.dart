import 'package:flutter/foundation.dart';

final homeRefreshBus = HomeRefreshBus();

class HomeRefreshBus extends ValueNotifier<int> {
  HomeRefreshBus() : super(0);

  bool _pendingRefresh = false;
  bool _newMediaBar = false;

  /// [newMediaBar] also loads a new set into the media bar, for a refresh the
  /// viewer asked for.
  void request({bool newMediaBar = false}) {
    _newMediaBar = _newMediaBar || newMediaBar;
    value = value + 1;
  }

  bool consumeNewMediaBar() {
    final newMediaBar = _newMediaBar;
    _newMediaBar = false;
    return newMediaBar;
  }

  void requestAfterNavigation() {
    _pendingRefresh = true;
  }

  void requestNowOrAfterNavigation() {
    if (hasListeners) {
      request();
    } else {
      requestAfterNavigation();
    }
  }

  bool consumePending() {
    if (!_pendingRefresh) {
      return false;
    }
    _pendingRefresh = false;
    return true;
  }
}
