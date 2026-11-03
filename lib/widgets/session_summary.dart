import 'package:flutter/material.dart';

import '../models/exercise.dart';
import '../models/workout_session.dart';
import '../util/format.dart';

/// One line per set: "W  10 × 45 lb".
List<String> setLines(WorkoutSession s, String displayUnit) {
  final lines = <String>[];
  for (var i = 0; i < s.sets.length; i++) {
    final set = s.sets[i];
    final reps = set.reps?.toString() ?? '–';
    final weight = set.weight == null
        ? '–'
        : fmtWeight(set.weight!, set.unit, displayUnit);
    lines.add('${set.warmup ? 'Warm-up' : 'Set ${i + 1}'}:  $reps × $weight');
  }
  return lines;
}

/// "Zone 2 time: 45:00" style lines for logged fields.
List<String> fieldLines(WorkoutSession s) {
  final lines = <String>[];
  for (final f in s.fields) {
    final v = f.value;
    if (v == null || (v is String && v.trim().isEmpty)) continue;
    final text = switch (f.type) {
      FieldType.duration => fmtClock((v as num).round()),
      FieldType.number => '${fmtNumber((v as num).toDouble())}'
          '${f.unit.isEmpty ? '' : ' ${f.unit}'}',
      FieldType.integer => '${(v as num).round()}'
          '${f.unit.isEmpty ? '' : ' ${f.unit}'}',
      FieldType.text => v.toString(),
    };
    lines.add('${f.label}: $text');
  }
  return lines;
}

/// A compact one-liner used on the home screen and in the "last time" row.
String shortSummary(WorkoutSession s, String displayUnit) {
  if (s.sets.isNotEmpty) {
    final working = s.sets.where((x) => !x.warmup).toList();
    final shown = working.isEmpty ? s.sets : working;
    final parts = shown.map((x) {
      final w = x.weight == null ? '' : '×${fmtNumber(convertWeight(x.weight!, x.unit, displayUnit))}';
      return '${x.reps ?? '–'}$w';
    });
    return '${shown.length} set${shown.length == 1 ? '' : 's'}: ${parts.join(', ')}';
  }
  final f = fieldLines(s);
  if (f.isNotEmpty) return f.join(' · ');
  return s.notes.isEmpty ? 'No details' : s.notes;
}

class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.session,
    required this.displayUnit,
    this.onDelete,
  });

  final WorkoutSession session;
  final String displayUnit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;
    final sets = setLines(s, displayUnit);
    final fields = fieldLines(s);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fmtDateTime(s.startedAt),
                          style: theme.textTheme.titleMedium),
                      Text(
                        'Took ${fmtDurationWords(s.durationSec)} '
                        '(${fmtTime(s.startedAt)} – ${fmtTime(s.finishedAt)})',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: s.synced ? 'Saved to Google Sheet' : 'Waiting to sync',
                  child: Icon(
                    s.synced ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
                    size: 20,
                    color: s.synced
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                ),
                if (onDelete != null)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'delete') onDelete!();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
              ],
            ),
            if (sets.isNotEmpty || fields.isNotEmpty) const SizedBox(height: 8),
            for (final line in sets) Text(line),
            for (final line in fields) Text(line),
            if (s.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                s.notes,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
