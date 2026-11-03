import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/exercise_store.dart';
import '../data/session_store.dart';
import '../data/settings.dart';
import '../models/exercise.dart';
import '../sync/sheets_sync.dart';
import '../util/format.dart';
import '../widgets/section_header.dart';
import 'exercise_screen.dart';
import 'settings_screen.dart';
import 'tracking_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final exercises = context.watch<ExerciseStore>();
    final sessions = context.watch<SessionStore>();
    final settings = context.watch<Settings>();
    final sync = context.watch<SheetsSync>();

    final categories = exercises.categories;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise Tracker'),
        actions: [
          _SyncButton(settings: settings, sessions: sessions, sync: sync),
          IconButton(
            tooltip: 'Tracking',
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TrackingScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: categories.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No exercises yet.\nAdd some in Settings ▸ Manage exercises.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                for (final category in categories) ...[
                  SectionHeader(category),
                  ..._tilesFor(context, exercises.inCategory(category), sessions),
                ],
              ],
            ),
    );
  }

  List<Widget> _tilesFor(
      BuildContext context, List<Exercise> list, SessionStore sessions) {
    final widgets = <Widget>[];
    final seenGroups = <String>{};
    for (final e in list) {
      final group = e.group;
      if (group == null) {
        widgets.add(_ExerciseTile(exercise: e, sessions: sessions));
      } else if (!seenGroups.contains(group)) {
        seenGroups.add(group);
        final members = list.where((x) => x.group == group).toList();
        widgets.add(
          ExpansionTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(group),
            subtitle: Text('${members.length} exercises'),
            childrenPadding: const EdgeInsets.only(left: 16),
            children: [
              for (final m in members) _ExerciseTile(exercise: m, sessions: sessions),
            ],
          ),
        );
      }
    }
    return widgets;
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({required this.exercise, required this.sessions});

  final Exercise exercise;
  final SessionStore sessions;

  @override
  Widget build(BuildContext context) {
    final last = sessions.lastFor(exercise.id);
    return ListTile(
      leading: Icon(exercise.hasSets
          ? Icons.fitness_center
          : exercise.fields.isEmpty
              ? Icons.notes_outlined
              : Icons.directions_run_outlined),
      title: Text(exercise.name),
      subtitle: Text(last == null
          ? 'Not logged yet'
          : 'Last: ${fmtDate(last.startedAt)} · ${fmtDurationWords(last.durationSec)}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ExerciseScreen(exerciseId: exercise.id)),
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  const _SyncButton(
      {required this.settings, required this.sessions, required this.sync});

  final Settings settings;
  final SessionStore sessions;
  final SheetsSync sync;

  @override
  Widget build(BuildContext context) {
    if (!settings.syncEnabled) return const SizedBox.shrink();
    final pending = sessions.pendingCount;
    final theme = Theme.of(context);

    Widget icon;
    String tip;
    if (sync.isSyncing) {
      icon = const SizedBox(
          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
      tip = 'Syncing…';
    } else if (settings.lastSyncError != null) {
      icon = Icon(Icons.cloud_off_outlined, color: theme.colorScheme.error);
      tip = 'Sync failed: ${settings.lastSyncError}. Tap to retry.';
    } else if (pending > 0) {
      icon = Badge(label: Text('$pending'), child: const Icon(Icons.cloud_upload_outlined));
      tip = '$pending waiting to sync. Tap to sync now.';
    } else {
      icon = const Icon(Icons.cloud_done_outlined);
      tip = 'Everything is in your Google Sheet';
    }

    return IconButton(
      tooltip: tip,
      icon: icon,
      onPressed: sync.isSyncing
          ? null
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              final err = await sync.pushPending();
              messenger.showSnackBar(SnackBar(
                content: Text(err == null ? 'Synced with Google Sheet' : 'Sync failed: $err'),
              ));
            },
    );
  }
}
