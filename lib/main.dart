import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/exercise_store.dart';
import 'data/session_store.dart';
import 'data/settings.dart';
import 'screens/home_screen.dart';
import 'sync/auto_sync.dart';
import 'sync/sheets_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final results = await Future.wait([
    Settings.load(),
    ExerciseStore.load(),
    SessionStore.load(),
  ]);
  final settings = results[0] as Settings;
  final exercises = results[1] as ExerciseStore;
  final sessions = results[2] as SessionStore;
  final sync = SheetsSync(store: sessions, settings: settings);

  runApp(ExerciseTrackerApp(
    settings: settings,
    exercises: exercises,
    sessions: sessions,
    sync: sync,
  ));

  // Everything is saved on the phone first. AutoSync keeps retrying the
  // Google Sheet push (on launch, on foreground, and on a timer) until
  // nothing is pending, so workouts logged offline arrive once there is
  // internet again.
  AutoSync(sync: sync, store: sessions, settings: settings).start();
}

class ExerciseTrackerApp extends StatelessWidget {
  const ExerciseTrackerApp({
    super.key,
    required this.settings,
    required this.exercises,
    required this.sessions,
    required this.sync,
  });

  final Settings settings;
  final ExerciseStore exercises;
  final SessionStore sessions;
  final SheetsSync sync;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1B6B5A);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: exercises),
        ChangeNotifierProvider.value(value: sessions),
        ChangeNotifierProvider.value(value: sync),
      ],
      child: MaterialApp(
        title: 'Exercise Tracker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seed),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        darkTheme: ThemeData(
          colorScheme:
              ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
