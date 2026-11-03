import 'dart:io';

import 'package:exercise_tracker/data/session_store.dart';
import 'package:exercise_tracker/data/settings.dart';
import 'package:exercise_tracker/models/workout_session.dart';
import 'package:exercise_tracker/sync/auto_sync.dart';
import 'package:exercise_tracker/sync/sheets_sync.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

WorkoutSession _s(String id) => WorkoutSession(
      id: id,
      exerciseId: 'squats',
      exerciseName: 'Squats',
      category: 'Strength Training',
      startedAt: DateTime(2026, 11, 1, 7),
      finishedAt: DateTime(2026, 11, 1, 7, 20),
      sets: [StrengthSet(reps: 5, weight: 135)],
    );

void main() {
  late Directory tmp;
  late Settings settings;
  late SessionStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('autosync');
    SharedPreferences.setMockInitialValues({'sheetUrl': 'https://script.google.com/macros/s/x/exec'});
    settings = await Settings.load();
    store = await SessionStore.loadFrom(File('${tmp.path}/s.json'));
  });
  tearDown(() => tmp.delete(recursive: true));

  testWidgets('offline saves stay local, then sync once the network is back', (tester) async {
    var online = false;
    var posts = 0;
    final client = MockClient((req) async {
      if (!online) throw const SocketException('offline');
      posts++;
      return http.Response('{"ok":true,"count":1}', 200);
    });
    final sync = SheetsSync(store: store, settings: settings, client: client);
    // Real (not fake) time: the retry timer is created from the store
    // listener, which fires after real file I/O inside runAsync.
    final auto = AutoSync(sync: sync, store: store, settings: settings,
        retryEvery: const Duration(milliseconds: 200));
    addTearDown(auto.dispose);
    addTearDown(sync.dispose);

    await tester.runAsync(() async {
      auto.start();
      await store.add(_s('a'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    // Saved on the phone, flagged pending, error recorded, nothing posted.
    expect(store.all.single.synced, isFalse);
    expect(store.pendingCount, 1);
    expect(settings.lastSyncError, 'No internet connection.');
    expect(posts, 0);

    // Network returns; the retry timer picks it up within one interval.
    online = true;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    expect(posts, 1);
    expect(store.all.single.synced, isTrue);
    expect(store.pendingCount, 0);
    expect(settings.lastSyncError, isNull);

    // Nothing pending: the timer stops and no more posts happen.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    expect(posts, 1);
  });

  testWidgets('returning to the foreground retries immediately', (tester) async {
    var online = false;
    var posts = 0;
    final client = MockClient((req) async {
      if (!online) throw const SocketException('offline');
      posts++;
      return http.Response('{"ok":true,"count":1}', 200);
    });
    final sync = SheetsSync(store: store, settings: settings, client: client);
    final auto = AutoSync(sync: sync, store: store, settings: settings,
        retryEvery: const Duration(hours: 1));
    addTearDown(auto.dispose);
    addTearDown(sync.dispose);

    await tester.runAsync(() async {
      auto.start();
      await store.add(_s('a'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(posts, 0);

    online = true;
    await tester.runAsync(() async {
      auto.didChangeAppLifecycleState(AppLifecycleState.paused);
      auto.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(posts, 1);
    expect(store.pendingCount, 0);
  });
}
