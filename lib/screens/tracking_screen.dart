import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/exercise_store.dart';
import '../data/session_store.dart';
import '../models/exercise.dart';
import '../models/workout_session.dart';
import '../util/format.dart';
import '../widgets/section_header.dart';
import 'exercise_screen.dart';

/// "How long since I did X?" for most exercises, and "how much in the past
/// week?" for exercises that opt into a weekly total (Zone 2 by default).
/// Exercises with the same tracking group share one row.
class TrackingScreen extends StatelessWidget {
  const TrackingScreen({super.key, this.now});

  /// Injectable clock for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final exercises = context.watch<ExerciseStore>();
    final sessions = context.watch<SessionStore>();
    final theme = Theme.of(context);
    final today = now ?? DateTime.now();

    final rows = _buildRows(exercises);

    return Scaffold(
      appBar: AppBar(title: const Text('Tracking')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          for (final category in exercises.categories)
            if (rows.any((r) => r.category == category)) ...[
              SectionHeader(category),
              for (final r in rows.where((r) => r.category == category))
                _TrackingRow(row: r, sessions: sessions, now: today),
            ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Text(
              'Days since the last session, or the total over the past 7 days for '
              'exercises set to track a weekly amount. Choose what each exercise '
              'shows, or hide it, in Settings ▸ Manage exercises.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /// One row per exercise, except that exercises sharing a tracking group
  /// collapse into one row placed where the first member sits.
  List<_Row> _buildRows(ExerciseStore store) {
    final rows = <_Row>[];
    final seenGroups = <String>{};
    for (final e in store.all) {
      if (!e.onTrackingTable) continue;
      final g = e.trackingGroup;
      if (g == null) {
        rows.add(_Row(title: e.name, category: e.category, members: [e]));
      } else if (seenGroups.add(g)) {
        final members = store.all
            .where((x) => x.onTrackingTable && x.trackingGroup == g)
            .toList();
        rows.add(_Row(title: g, category: e.category, members: members));
      }
    }
    return rows;
  }
}

class _Row {
  _Row({required this.title, required this.category, required this.members});
  final String title;
  final String category;
  final List<Exercise> members;
}

class _TrackingRow extends StatelessWidget {
  const _TrackingRow({required this.row, required this.sessions, required this.now});

  final _Row row;
  final SessionStore sessions;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Most recent session across the row's members.
    WorkoutSession? last;
    Exercise? lastExercise;
    for (final e in row.members) {
      final l = sessions.lastFor(e.id);
      if (l != null && (last == null || l.startedAt.isAfter(last.startedAt))) {
        last = l;
        lastExercise = e;
      }
    }

    // Weekly mode applies to a single exercise that tracks a weekly total.
    final single = row.members.length == 1 ? row.members.first : null;
    final weeklyField = single?.weeklyTotalField == null
        ? null
        : single!.fields.where((f) => f.key == single.weeklyTotalField).firstOrNull;

    String value;
    String? detail;
    bool stale;
    if (weeklyField != null) {
      final secs = weeklyTotalSeconds(sessions.forExercise(single!.id), weeklyField.key, now);
      value = '${(secs / 60).round()} min';
      detail = '${weeklyField.label}, past 7 days';
      stale = secs == 0;
    } else {
      final days = last == null ? null : calendarDaysBetween(last.startedAt, now);
      value = fmtDaysSince(days);
      detail = last == null
          ? null
          : row.members.length > 1
              ? 'Last ${fmtDate(last.startedAt)} (${lastExercise!.name})'
              : 'Last ${fmtDate(last.startedAt)}';
      stale = days == null || days > 7;
    }

    final open = lastExercise ?? row.members.first;
    return ListTile(
      dense: true,
      title: Text(row.title),
      subtitle: detail == null ? null : Text(detail),
      trailing: Text(
        value,
        style: theme.textTheme.titleMedium?.copyWith(
          color: stale ? theme.colorScheme.error : theme.colorScheme.primary,
        ),
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ExerciseScreen(exerciseId: open.id),
      )),
    );
  }
}
