import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../data/exercise_store.dart';
import '../data/session_store.dart';
import '../data/settings.dart';
import '../models/exercise.dart';
import '../models/workout_session.dart';
import '../util/format.dart';
import '../widgets/section_header.dart';
import '../widgets/session_summary.dart';
import 'history_screen.dart';

const int kDefaultSetCount = 5;

/// The logging screen for one exercise. The clock starts when the screen
/// opens and stops when you hit Submit.
class ExerciseScreen extends StatefulWidget {
  const ExerciseScreen({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _SetRow {
  final reps = TextEditingController();
  final weight = TextEditingController();
  bool warmup = false;

  bool get isEmpty => reps.text.trim().isEmpty && weight.text.trim().isEmpty;

  void dispose() {
    reps.dispose();
    weight.dispose();
  }
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  late final DateTime _openedAt;
  late final Timer _ticker;
  Duration _elapsed = Duration.zero;

  final List<_SetRow> _sets = [];
  final Map<String, TextEditingController> _fieldCtrls = {};
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed = DateTime.now().difference(_openedAt));
    });
    final exercise = context.read<ExerciseStore>().byId(widget.exerciseId);
    if (exercise != null) {
      if (exercise.hasSets) {
        for (var i = 0; i < kDefaultSetCount; i++) {
          _sets.add(_SetRow());
        }
      }
      for (final f in exercise.fields) {
        _fieldCtrls[f.key] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    _ticker.cancel();
    for (final s in _sets) {
      s.dispose();
    }
    for (final c in _fieldCtrls.values) {
      c.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  /// Warm-ups are always the first sets. Ticking row [i] also ticks every
  /// row above it; unticking it also clears every row below it.
  void _setWarmup(int i, bool warmup) {
    setState(() {
      if (warmup) {
        for (var j = 0; j <= i; j++) {
          _sets[j].warmup = true;
        }
      } else {
        for (var j = i; j < _sets.length; j++) {
          _sets[j].warmup = false;
        }
      }
    });
  }

  bool get _hasInput =>
      _sets.any((s) => !s.isEmpty) ||
      _fieldCtrls.values.any((c) => c.text.trim().isNotEmpty) ||
      _notes.text.trim().isNotEmpty;

  Future<bool> _confirmDiscard() async {
    if (!_hasInput) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this workout?'),
        content: const Text("What you've entered won't be saved."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return ok ?? false;
  }

  Object? _parseField(FieldDef f, String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    return switch (f.type) {
      FieldType.duration => f.entersSeconds
          ? (double.tryParse(s) == null || double.parse(s) < 0 ? null : double.parse(s).round())
          : parseMinutesToSeconds(s),
      FieldType.number => double.tryParse(s),
      FieldType.integer => int.tryParse(s) ?? double.tryParse(s)?.round(),
      FieldType.text => s,
    };
  }

  Future<void> _submit(Exercise exercise) async {
    FocusScope.of(context).unfocus();
    final settings = context.read<Settings>();
    final store = context.read<SessionStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Validate fields before saving anything.
    final fieldValues = <FieldValue>[];
    for (final f in exercise.fields) {
      final raw = _fieldCtrls[f.key]?.text ?? '';
      final v = _parseField(f, raw);
      if (raw.trim().isNotEmpty && v == null) {
        messenger.showSnackBar(SnackBar(content: Text("Couldn't read \"${f.label}\": $raw")));
        return;
      }
      fieldValues.add(FieldValue.of(f, v));
    }

    final sets = <StrengthSet>[];
    for (final row in _sets) {
      if (row.isEmpty) continue;
      final reps = int.tryParse(row.reps.text.trim());
      final weight = double.tryParse(row.weight.text.trim());
      if (row.reps.text.trim().isNotEmpty && reps == null) {
        messenger.showSnackBar(SnackBar(content: Text("Reps must be a whole number: ${row.reps.text}")));
        return;
      }
      if (row.weight.text.trim().isNotEmpty && weight == null) {
        messenger.showSnackBar(SnackBar(content: Text("Weight must be a number: ${row.weight.text}")));
        return;
      }
      sets.add(StrengthSet(
        reps: reps,
        weight: weight,
        unit: settings.weightUnit,
        warmup: row.warmup,
      ));
    }

    final firstWorking = sets.indexWhere((s) => !s.warmup);
    if (firstWorking >= 0 && sets.skip(firstWorking).any((s) => s.warmup)) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Warm-up sets have to come before the first working set.'),
      ));
      return;
    }

    if (!_hasInput) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nothing entered'),
          content: const Text('Save this workout with just the time?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _saving = true);
    final finishedAt = DateTime.now();
    final session = WorkoutSession(
      id: const Uuid().v4(),
      exerciseId: exercise.id,
      exerciseName: exercise.name,
      category: exercise.category,
      startedAt: _openedAt,
      finishedAt: finishedAt,
      notes: _notes.text.trim(),
      sets: sets,
      fields: fieldValues,
    );
    await store.add(session);

    messenger.showSnackBar(SnackBar(
      content: Text('${exercise.name} saved · took ${fmtDurationWords(session.durationSec)}'),
    ));
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final exercise = context.watch<ExerciseStore>().byId(widget.exerciseId);
    final settings = context.watch<Settings>();
    final sessions = context.watch<SessionStore>();
    final theme = Theme.of(context);

    if (exercise == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This exercise no longer exists.')),
      );
    }

    final last = sessions.lastFor(exercise.id);
    final unit = settings.weightUnit;

    return PopScope(
      canPop: !_hasInput,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (!discard || !context.mounted) return;
        Navigator.of(context).pop();
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          appBar: AppBar(
            title: Text(exercise.name),
            actions: [
              IconButton(
                tooltip: 'History',
                icon: const Icon(Icons.history),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => HistoryScreen(exerciseId: exercise.id),
                )),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(28),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timer_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      'Started ${fmtTime(_openedAt)}  ·  ${fmtClock(_elapsed.inSeconds)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              if (last != null)
                _LastTimePanel(
                  session: last,
                  unit: unit,
                  initiallyExpanded: settings.lastTimeExpanded,
                  onExpansionChanged: settings.setLastTimeExpanded,
                  onViewHistory: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => HistoryScreen(exerciseId: exercise.id),
                  )),
                ),
              if (exercise.hasSets) ...[
                SectionHeader('Sets'),
                _SetsHeader(unit: unit),
                for (var i = 0; i < _sets.length; i++)
                  _SetRowWidget(
                    index: i,
                    row: _sets[i],
                    unit: unit,
                    onWarmupChanged: (v) => _setWarmup(i, v),
                    isLast: i == _sets.length - 1,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _sets.add(_SetRow())),
                      icon: const Icon(Icons.add),
                      label: const Text('Add set'),
                    ),
                  ),
                ),
              ],
              if (exercise.fields.isNotEmpty) ...[
                SectionHeader(exercise.hasSets ? 'Details' : 'Workout'),
                for (final f in exercise.fields)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: _FieldInput(def: f, controller: _fieldCtrls[f.key]!),
                  ),
              ],
              if (!exercise.hasSets && exercise.fields.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    'Logs the time you spent plus your notes below.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              SectionHeader('Notes'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _notes,
                  minLines: 3,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'How did it go?',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _submit(exercise),
                  icon: const Icon(Icons.check),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Submit'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What you did last time, shown above the inputs so you can match or beat it.
class _LastTimePanel extends StatelessWidget {
  const _LastTimePanel({
    required this.session,
    required this.unit,
    required this.initiallyExpanded,
    required this.onExpansionChanged,
    required this.onViewHistory,
  });

  final WorkoutSession session;
  final String unit;
  final bool initiallyExpanded;
  final ValueChanged<bool> onExpansionChanged;
  final VoidCallback onViewHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;
    final sets = setLines(s, unit);
    final fields = fieldLines(s);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      color: theme.colorScheme.surfaceContainerHigh,
      child: ExpansionTile(
        key: PageStorageKey('lastTime-${s.exerciseId}'),
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpansionChanged,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.history),
        title: Text('Last time · ${fmtDate(s.startedAt)}'),
        subtitle: Text(
          'Took ${fmtDurationWords(s.durationSec)} · ${shortSummary(s, unit)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: muted,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${fmtDateTime(s.startedAt)} – ${fmtTime(s.finishedAt)}',
            style: muted,
          ),
          if (sets.isNotEmpty || fields.isNotEmpty) const SizedBox(height: 6),
          for (final line in sets) Text(line, style: theme.textTheme.bodyMedium),
          for (final line in fields) Text(line, style: theme.textTheme.bodyMedium),
          if (s.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              s.notes,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (sets.isEmpty && fields.isEmpty && s.notes.trim().isEmpty)
            Text('No details were logged.', style: muted),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onViewHistory,
              child: const Text('All history'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetsHeader extends StatelessWidget {
  const _SetsHeader({required this.unit});
  final String unit;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text('#', style: style)),
          SizedBox(width: 56, child: Text('Warm-up', style: style, textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          Expanded(child: Text('Reps', style: style)),
          const SizedBox(width: 8),
          Expanded(child: Text('Weight ($unit)', style: style)),
        ],
      ),
    );
  }
}

class _SetRowWidget extends StatelessWidget {
  const _SetRowWidget({
    required this.index,
    required this.row,
    required this.unit,
    required this.onWarmupChanged,
    required this.isLast,
  });

  final int index;
  final _SetRow row;
  final String unit;
  final ValueChanged<bool> onWarmupChanged;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text('${index + 1}')),
          SizedBox(
            width: 56,
            child: Checkbox(
              value: row.warmup,
              onChanged: (v) => onWarmupChanged(v ?? false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: row.reps,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'reps'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: row.weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
              decoration: InputDecoration(hintText: unit),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldInput extends StatelessWidget {
  const _FieldInput({required this.def, required this.controller});

  final FieldDef def;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final (keyboard, suffix, hint) = switch (def.type) {
      FieldType.duration => (
          const TextInputType.numberWithOptions(decimal: true),
          def.entersSeconds ? 'sec' : 'min',
          def.entersSeconds ? 'seconds, e.g. 45' : 'minutes, e.g. 1.5',
        ),
      FieldType.number => (
          const TextInputType.numberWithOptions(decimal: true),
          def.unit,
          null,
        ),
      FieldType.integer => (TextInputType.number, def.unit, null),
      FieldType.text => (TextInputType.text, '', null),
    };
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      textInputAction: TextInputAction.next,
      textCapitalization: def.type == FieldType.text
          ? TextCapitalization.sentences
          : TextCapitalization.none,
      decoration: InputDecoration(
        labelText: def.label,
        suffixText: suffix.isEmpty ? null : suffix,
        hintText: hint,
      ),
    );
  }
}
