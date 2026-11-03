import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/exercise_store.dart';
import '../data/session_store.dart';
import '../data/settings.dart';
import '../models/workout_session.dart';
import '../widgets/session_summary.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.exerciseId});

  final String exerciseId;

  Future<void> _delete(BuildContext context, WorkoutSession s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this session?'),
        content: const Text(
            'It will be removed from your phone and from the Google Sheet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<SessionStore>().delete(s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionStore>().forExercise(exerciseId);
    final unit = context.watch<Settings>().weightUnit;
    final exercise = context.watch<ExerciseStore>().byId(exerciseId);
    final name = exercise?.name ??
        (sessions.isNotEmpty ? sessions.first.exerciseName : 'History');

    return Scaffold(
      appBar: AppBar(title: Text('$name · History')),
      body: sessions.isEmpty
          ? const Center(child: Text('No sessions logged yet.'))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: sessions.length,
              itemBuilder: (ctx, i) => SessionCard(
                session: sessions[i],
                displayUnit: unit,
                onDelete: () => _delete(context, sessions[i]),
              ),
            ),
    );
  }
}
