import 'dart:io';

import 'package:exercise_tracker/data/exercise_store.dart';
import 'package:exercise_tracker/data/session_store.dart';
import 'package:exercise_tracker/data/settings.dart';
import 'package:exercise_tracker/main.dart';
import 'package:exercise_tracker/models/exercise.dart';
import 'package:exercise_tracker/models/workout_session.dart';
import 'package:exercise_tracker/sync/sheets_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  late Settings settings;
  late ExerciseStore exercises;
  late SessionStore sessions;
  late SheetsSync sync;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('et_widget');
    SharedPreferences.setMockInitialValues({'sheetUrl': ''});
    settings = await Settings.load();
    exercises = await ExerciseStore.loadFrom(File('${tmp.path}/exercises.json'));
    sessions = await SessionStore.loadFrom(File('${tmp.path}/sessions.json'));
    sync = SheetsSync(store: sessions, settings: settings);
  });

  tearDown(() async {
    sync.dispose();
    await tmp.delete(recursive: true);
  });

  Widget app() => ExerciseTrackerApp(
        settings: settings,
        exercises: exercises,
        sessions: sessions,
        sync: sync,
      );

  /// Tap a button whose handler persists to disk. Widget tests run in a
  /// fake-async zone where real file I/O never completes, so run the tap
  /// (and a moment of real time) in [WidgetTester.runAsync].
  Future<void> tapAndFlush(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.runAsync(() async {
      await tester.tap(finder);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
  }

  /// Use a tall phone-sized surface so lazy lists build every row.
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
  }

  testWidgets('home shows categories, groups and exercises', (tester) async {
    await pumpApp(tester);
    expect(find.text('CARDIO'), findsOneWidget);
    expect(find.text('STRENGTH TRAINING'), findsOneWidget);
    expect(find.text('Squats'), findsOneWidget);
    expect(find.text('Pull Ups & Chin Ups'), findsOneWidget);
    expect(find.text('Pull Ups'), findsNothing); // collapsed until tapped

    await tester.tap(find.text('Pull Ups & Chin Ups'));
    await tester.pumpAndSettle();
    expect(find.text('Pull Ups'), findsOneWidget);
    expect(find.text('Chin Ups'), findsOneWidget);
  });

  testWidgets('log a strength workout with five default sets plus one', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();

    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'reps'), findsNWidgets(5));

    await tester.tap(find.text('Add set'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'reps'), findsNWidgets(6));

    // Warm-up set then two working sets; the rest are left blank.
    final reps = find.widgetWithText(TextField, 'reps');
    final weights = find.widgetWithText(TextField, 'lb');
    await tester.tap(find.byType(Checkbox).first);
    await tester.enterText(reps.at(0), '10');
    await tester.enterText(weights.at(0), '45');
    await tester.enterText(reps.at(1), '5');
    await tester.enterText(weights.at(1), '135');
    await tester.enterText(reps.at(2), '5');
    await tester.enterText(weights.at(2), '135');
    await tester.enterText(find.widgetWithText(TextField, 'How did it go?'), 'Solid');

    await tapAndFlush(tester, find.text('Submit'));

    final saved = sessions.forExercise('bench_press');
    expect(saved.length, 1);
    expect(saved.single.sets.length, 3); // blank rows are dropped
    expect(saved.single.sets.first.warmup, isTrue);
    expect(saved.single.sets[1].weight, 135);
    expect(saved.single.sets[1].unit, 'lb');
    expect(saved.single.notes, 'Solid');
    expect(saved.single.finishedAt.isAfter(saved.single.startedAt) ||
        saved.single.finishedAt.isAtSameMomentAs(saved.single.startedAt), isTrue);

    // Back on home: the tile now shows when it was last done.
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.textContaining('Last:'), findsOneWidget);
  });

  testWidgets('reopening an exercise shows last time in a collapsible panel', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Squats'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Last time'), findsNothing);

    await tester.tap(find.byType(Checkbox).first);
    await tester.enterText(find.widgetWithText(TextField, 'reps').at(0), '8');
    await tester.enterText(find.widgetWithText(TextField, 'lb').at(0), '95');
    await tester.enterText(find.widgetWithText(TextField, 'reps').at(1), '5');
    await tester.enterText(find.widgetWithText(TextField, 'lb').at(1), '185');
    await tester.enterText(find.widgetWithText(TextField, 'How did it go?'), 'Knees felt fine');
    await tapAndFlush(tester, find.text('Submit'));

    await tester.tap(find.text('Squats'));
    await tester.pumpAndSettle();
    // Open by default, with every set and the notes visible.
    expect(find.textContaining('Last time ·'), findsOneWidget);
    expect(find.text('Warm-up:  8 × 95 lb'), findsOneWidget);
    expect(find.text('Set 2:  5 × 185 lb'), findsOneWidget);
    expect(find.text('Knees felt fine'), findsOneWidget);

    // Collapsing hides the details and is remembered.
    await tester.tap(find.textContaining('Last time ·'));
    await tester.pumpAndSettle();
    expect(find.text('Set 2:  5 × 185 lb'), findsNothing);
    expect(settings.lastTimeExpanded, isFalse);
  });

  testWidgets('tracking table shows days since, or minutes over the past week', (tester) async {
    final now = DateTime.now();
    WorkoutSession z(String id, Duration ago, int minutes) => WorkoutSession(
          id: id, exerciseId: 'zone2_cardio', exerciseName: 'Zone 2 Cardio', category: 'Cardio',
          startedAt: now.subtract(ago), finishedAt: now.subtract(ago),
          fields: [FieldValue(key: 'zone2_time', label: 'Zone 2 time',
              type: FieldType.duration, value: minutes * 60)],
        );
    await tester.runAsync(() async {
      await sessions.add(z('z1', const Duration(hours: 1), 45));
      await sessions.add(z('z2', const Duration(days: 3), 67));
      await sessions.add(z('z3', const Duration(days: 9), 60)); // outside the week
      await sessions.add(WorkoutSession(
        id: 's1', exerciseId: 'squats', exerciseName: 'Squats', category: 'Strength Training',
        startedAt: now.subtract(const Duration(days: 6)), finishedAt: now.subtract(const Duration(days: 6)),
        sets: [StrengthSet(reps: 5, weight: 135)],
      ));
      await sessions.add(WorkoutSession(
        id: 'd1', exerciseId: 'deadlifts', exerciseName: 'Deadlifts', category: 'Strength Training',
        startedAt: now.subtract(const Duration(days: 45)), finishedAt: now.subtract(const Duration(days: 45)),
      ));
      await sessions.add(WorkoutSession(
        id: 'c1', exerciseId: 'chin_ups', exerciseName: 'Chin Ups', category: 'Strength Training',
        startedAt: now.subtract(const Duration(days: 12)), finishedAt: now.subtract(const Duration(days: 12)),
      ));
      await sessions.add(WorkoutSession(
        id: 'b1', exerciseId: 'bicep_curls', exerciseName: 'Bicep Curls', category: 'Strength Training',
        startedAt: now.subtract(const Duration(days: 2)), finishedAt: now.subtract(const Duration(days: 2)),
      ));
    });

    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.table_chart_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Tracking'), findsOneWidget);
    expect(find.text('112 min'), findsOneWidget); // zone 2: 45 + 67, not the 60 from 9 days ago
    expect(find.text('Zone 2 time, past 7 days'), findsOneWidget);
    expect(find.text('6 days'), findsOneWidget); // squats
    expect(find.text('More than a month'), findsOneWidget); // deadlifts
    expect(find.text('Never'), findsWidgets); // the rest
    expect(find.text('Other'), findsNothing); // hidden, and its empty category too
    expect(find.text('OTHER'), findsNothing);

    // Chin ups and bicep curls share one row showing the more recent of the two.
    expect(find.text('Chin Ups & Bicep Curls'), findsOneWidget);
    expect(find.text('Chin Ups'), findsNothing);
    expect(find.text('Bicep Curls'), findsNothing);
    expect(find.text('2 days'), findsOneWidget);
    expect(find.textContaining('(Bicep Curls)'), findsOneWidget);
  });

  testWidgets('warm-ups are always the first sets', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Squats'));
    await tester.pumpAndSettle();

    List<bool> checked() =>
        tester.widgetList<Checkbox>(find.byType(Checkbox)).map((c) => c.value == true).toList();

    // Ticking row 3 also ticks rows 1 and 2.
    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pumpAndSettle();
    expect(checked(), [true, true, true, false, false]);

    // Unticking row 2 clears rows 2 and 3, leaving only row 1.
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(checked(), [true, false, false, false, false]);

    // A new row added below starts as a working set.
    await tester.tap(find.text('Add set'));
    await tester.pumpAndSettle();
    expect(checked(), [true, false, false, false, false, false]);
  });

  testWidgets('log interval training fields', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Cardio Interval Training'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'reps'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Ramp up time'), '45');
    await tester.enterText(find.widgetWithText(TextField, 'Stable intense work time'), '100');
    await tester.enterText(find.widgetWithText(TextField, 'Less intense time'), '70');
    await tester.enterText(find.widgetWithText(TextField, 'Ramp up speed'), '6.5');
    await tester.enterText(find.widgetWithText(TextField, 'Stable speed'), '8');
    await tester.enterText(find.widgetWithText(TextField, 'Cycles'), '4');
    await tester.enterText(find.widgetWithText(TextField, 'Zone 5 time'), '12');

    await tapAndFlush(tester, find.text('Submit'));

    final s = sessions.forExercise('cardio_intervals').single;
    final byKey = {for (final f in s.fields) f.key: f.value};
    expect(byKey['ramp_up_time'], 45); // entered in seconds
    expect(byKey['work_time'], 100);
    expect(byKey['easy_time'], 70);
    expect(byKey['ramp_up_mph'], 6.5);
    expect(byKey['cycles'], 4);
    expect(byKey['zone5_time'], 720);
  });

  testWidgets('history lists the session and settings can switch units', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Deadlifts'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'reps').first, '3');
    await tester.enterText(find.widgetWithText(TextField, 'lb').first, '225');
    await tapAndFlush(tester, find.text('Submit'));

    // Switch to kg in settings.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tapAndFlush(tester, find.text('Kilograms (kg)'));
    expect(settings.weightUnit, 'kg');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // History converts for display.
    await tester.tap(find.text('Deadlifts'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.history)));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 × 102.1 kg'), findsOneWidget);
  });

  testWidgets('add a new exercise with a custom field from settings', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage exercises'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New exercise'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'e.g. Overhead Squat'), 'Rowing Machine');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Cardio'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sets with reps and weight'));
    await tester.tap(find.text('Sets with reps and weight'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Add field'));
    await tester.tap(find.text('Add field'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Label'), 'Distance');
    await tester.enterText(find.widgetWithText(TextField, 'Unit (optional)'), 'm');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Distance'), findsOneWidget);

    await tapAndFlush(tester, find.widgetWithText(TextButton, 'Save'));

    final e = exercises.byId('rowing_machine');
    expect(e, isNotNull);
    expect(e!.category, 'Cardio');
    expect(e.hasSets, isFalse);
    expect(e.fields.single.key, 'distance');
    expect(e.fields.single.unit, 'm');

    // It shows up on the home screen under Cardio.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Rowing Machine'), findsOneWidget);
  });
}
