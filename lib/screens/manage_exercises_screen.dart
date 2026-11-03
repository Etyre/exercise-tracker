import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/exercise_store.dart';
import '../models/exercise.dart';
import 'edit_exercise_screen.dart';

class ManageExercisesScreen extends StatelessWidget {
  const ManageExercisesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExerciseStore>();
    final list = store.all;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage exercises')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Tap an exercise to edit its name, category or fields. '
              'Drag the handle to reorder.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: list.length,
              onReorderItem: (from, to) => store.move(from, to),
              itemBuilder: (ctx, i) {
                final e = list[i];
                return ListTile(
                  key: ValueKey(e.id),
                  leading: Icon(e.hasSets
                      ? Icons.fitness_center
                      : Icons.directions_run_outlined),
                  title: Text(e.name),
                  subtitle: Text(_describe(e)),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_handle),
                  ),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EditExerciseScreen(exerciseId: e.id),
                  )),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const EditExerciseScreen(),
        )),
        icon: const Icon(Icons.add),
        label: const Text('New exercise'),
      ),
    );
  }

  String _describe(Exercise e) {
    final parts = <String>[e.category];
    if (e.group != null) parts.add(e.group!);
    final what = <String>[];
    if (e.hasSets) what.add('sets');
    if (e.fields.isNotEmpty) {
      what.add('${e.fields.length} field${e.fields.length == 1 ? '' : 's'}');
    }
    if (what.isNotEmpty) parts.add(what.join(' + '));
    return parts.join(' · ');
  }
}
