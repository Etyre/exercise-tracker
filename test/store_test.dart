import 'dart:convert';
import 'dart:io';

import 'package:exercise_tracker/data/exercise_catalog.dart';

import 'package:exercise_tracker/data/exercise_store.dart';
import 'package:exercise_tracker/data/session_store.dart';
import 'package:exercise_tracker/models/exercise.dart';
import 'package:exercise_tracker/models/workout_session.dart';
import 'package:flutter_test/flutter_test.dart';

WorkoutSession _session(String id, {bool synced = false}) => WorkoutSession(
      id: id,
      exerciseId: 'squats',
      exerciseName: 'Squats',
      category: 'Strength Training',
      startedAt: DateTime(2026, 10, 31, 7, 0),
      finishedAt: DateTime(2026, 10, 31, 7, 23, 10),
      notes: 'felt good',
      sets: [
        StrengthSet(reps: 10, weight: 45, warmup: true),
        StrengthSet(reps: 5, weight: 135),
      ],
      fields: [
        FieldValue(key: 'zone2_time', label: 'Zone 2 time', type: FieldType.duration, value: 2700),
        FieldValue(key: 'stable_mph', label: 'Stable speed', type: FieldType.number, unit: 'mph', value: 7.5),
      ],
      synced: synced,
    );

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('et_test'));
  tearDown(() async => tmp.delete(recursive: true));

  test('session JSON round-trips', () {
    final s = _session('a');
    final back = WorkoutSession.fromJson(s.toJson());
    expect(back.id, 'a');
    expect(back.exerciseName, 'Squats');
    expect(back.durationSec, 23 * 60 + 10);
    expect(back.sets.length, 2);
    expect(back.sets.first.warmup, isTrue);
    expect(back.sets.last.weight, 135);
    expect(back.fields.length, 2);
    expect(back.fields.first.type, FieldType.duration);
    expect(back.fields.first.value, 2700);
    expect(back.fields.last.unit, 'mph');
    expect(back.notes, 'felt good');
  });

  test('session store persists, syncs and deletes', () async {
    final file = File('${tmp.path}/sessions.json');
    var store = await SessionStore.loadFrom(file);
    await store.add(_session('a'));
    await store.add(_session('b'));
    expect(store.pendingCount, 2);

    await store.markSynced(['a']);
    expect(store.unsynced.map((s) => s.id), ['b']);

    await store.delete(store.all.firstWhere((s) => s.id == 'a'));
    expect(store.pendingDeletes, {'a'});
    expect(store.pendingCount, 2); // 1 unsynced + 1 pending delete

    // Reload from disk.
    store = await SessionStore.loadFrom(file);
    expect(store.all.map((s) => s.id), ['b']);
    expect(store.pendingDeletes, {'a'});

    // Remote merge: known and tombstoned ids are skipped, new ones marked synced.
    final added = await store.mergeRemote([_session('a'), _session('b'), _session('c')]);
    expect(added, 1);
    expect(store.all.firstWhere((s) => s.id == 'c').synced, isTrue);
    expect(store.lastFor('squats')?.id, isNotNull);
  });

  test('existing installs get exercises added in later versions', () async {
    final file = File('${tmp.path}/exercises.json');
    // Simulate a v1 install that never had "Other".
    final v1 = defaultExercises().where((e) => e.id != 'other').toList();
    for (final e in v1) {
      e.weeklyTotalField = null;
      e.trackingGroup = null;
      for (final f in e.fields) {
        if (f.isDuration) f.unit = '';
      }
    }
    file.writeAsStringSync(jsonEncode({
      'version': 1,
      'exercises': v1.map((e) => e.toJson()).toList(),
    }));
    var store = await ExerciseStore.loadFrom(file);
    expect(store.byId('other'), isNotNull);
    expect(store.all.length, 11);
    // v3 update: Zone 2 now tracks weekly minutes.
    expect(store.byId('zone2_cardio')!.weeklyTotalField, 'zone2_time');
    // v4 update: "Other" is hidden from the tracking table.
    expect(store.byId('other')!.onTrackingTable, isFalse);
    // v5 update: chin ups and bicep curls share a row.
    expect(store.byId('bicep_curls')!.trackingGroup, 'Chin Ups & Bicep Curls');
    // v6 update: interval ramp/work/easy times switch to seconds.
    final iv = store.byId('cardio_intervals')!;
    expect(iv.fields.where((f) => f.entersSeconds).map((f) => f.key),
        ['ramp_up_time', 'work_time', 'easy_time']);

    // Deleting it sticks: the migration doesn't run twice.
    await store.remove('other');
    store = await ExerciseStore.loadFrom(file);
    expect(store.byId('other'), isNull);
  });

  test('exercise store seeds defaults and edits persist', () async {
    final file = File('${tmp.path}/exercises.json');
    var store = await ExerciseStore.loadFrom(file);
    expect(store.all.length, 11);
    expect(store.categories, ['Cardio', 'Strength Training', 'Other']);
    expect(store.byId('other')!.hasSets, isFalse);
    expect(store.byId('other')!.fields, isEmpty);
    expect(store.byId('zone2_cardio')!.weeklyTotalField, 'zone2_time');
    expect(store.byId('cardio_intervals')!.weeklyTotalField, isNull);
    expect(store.byId('other')!.onTrackingTable, isFalse);
    expect(store.byId('squats')!.onTrackingTable, isTrue);
    expect(store.byId('chin_ups')!.trackingGroup, 'Chin Ups & Bicep Curls');
    expect(store.byId('bicep_curls')!.trackingGroup, 'Chin Ups & Bicep Curls');
    expect(store.byId('pull_ups')!.trackingGroup, isNull);
    expect(store.byId('cardio_intervals')!.fields.length, 7);
    expect(store.byId('cardio_intervals')!.fields.first.entersSeconds, isTrue);
    expect(store.byId('cardio_intervals')!.fields.last.entersSeconds, isFalse); // zone 5 in minutes
    expect(store.byId('pull_ups')!.group, 'Pull Ups & Chin Ups');

    final id = store.newId('Overhead Squat');
    expect(id, 'overhead_squat');
    await store.add(Exercise(
      id: id,
      name: 'Overhead Squat',
      category: 'Strength Training',
      hasSets: true,
      fields: [FieldDef(key: 'rpe', label: 'RPE', type: FieldType.integer)],
    ));
    expect(store.newId('Overhead Squat'), 'overhead_squat_2');

    final zone2 = store.byId('zone2_cardio')!.copy()
      ..name = 'Zone 2'
      ..fields.add(FieldDef(key: 'avg_hr', label: 'Average HR', type: FieldType.integer, unit: 'bpm'));
    await store.update(zone2);
    await store.move(0, 11);

    store = await ExerciseStore.loadFrom(file);
    expect(store.all.length, 12);
    expect(store.byId('zone2_cardio')!.name, 'Zone 2');
    expect(store.byId('zone2_cardio')!.fields.map((f) => f.key), ['zone2_time', 'avg_hr']);
    expect(store.byId('overhead_squat')!.fields.single.type, FieldType.integer);
    expect(store.all.last.id, 'cardio_intervals');
    expect(store.all[9].id, 'other');

    await store.remove('squats');
    expect(store.byId('squats'), isNull);
  });
}
