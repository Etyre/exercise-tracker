import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/session_store.dart';
import '../data/settings.dart';
import 'sheets_sync.dart';

/// Keeps retrying the Google Sheet push until nothing is pending.
///
/// Sessions are always saved on the phone first. This just makes sure they
/// reach the sheet once the network is back, without the user doing anything:
///   - on launch and whenever the app returns to the foreground,
///   - every [retryEvery] while the app is open and something is unsynced
///     (an offline attempt fails in well under a second, so this is cheap),
///   - immediately whenever a session is saved or the sheet URL changes
///     ([SheetsSync] already listens for that; this adds the retry loop).
class AutoSync with WidgetsBindingObserver {
  AutoSync({
    required this.sync,
    required this.store,
    required this.settings,
    this.retryEvery = const Duration(seconds: 45),
  });

  final SheetsSync sync;
  final SessionStore store;
  final Settings settings;
  final Duration retryEvery;

  Timer? _timer;
  bool _inForeground = true;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    store.addListener(_reschedule);
    settings.addListener(_reschedule);
    _kick();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(_reschedule);
    settings.removeListener(_reschedule);
    _timer?.cancel();
    _timer = null;
  }

  bool get _hasWork => settings.syncEnabled && store.pendingCount > 0;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _inForeground = true;
        _kick();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        _inForeground = state == AppLifecycleState.inactive;
        if (!_inForeground) _stopTimer();
    }
  }

  /// Try now, then keep a retry timer alive only while there is work to do.
  void _kick() {
    if (_hasWork && !sync.isSyncing) sync.pushPending();
    _reschedule();
  }

  void _reschedule() {
    if (!_hasWork || !_inForeground) {
      _stopTimer();
      return;
    }
    _timer ??= Timer.periodic(retryEvery, (_) {
      if (!_hasWork) {
        _stopTimer();
      } else if (!sync.isSyncing) {
        sync.pushPending();
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }
}
