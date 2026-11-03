import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/exercise_catalog.dart';
import '../data/exercise_store.dart';
import '../data/session_store.dart';
import '../models/exercise.dart';
import '../models/units.dart';
import '../widgets/section_header.dart';

/// Create a new exercise kind (no [exerciseId]) or edit an existing one.
class EditExerciseScreen extends StatefulWidget {
  const EditExerciseScreen({super.key, this.exerciseId});

  final String? exerciseId;

  @override
  State<EditExerciseScreen> createState() => _EditExerciseScreenState();
}

class _EditExerciseScreenState extends State<EditExerciseScreen> {
  late final Exercise _draft;
  late final bool _isNew;
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _group;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final store = context.read<ExerciseStore>();
    final existing = widget.exerciseId == null ? null : store.byId(widget.exerciseId!);
    _isNew = existing == null;
    _draft = existing?.copy() ??
        Exercise(id: '', name: '', category: kStrength, hasSets: true);
    _name = TextEditingController(text: _draft.name);
    _category = TextEditingController(text: _draft.category);
    _group = TextEditingController(text: _draft.group ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _group.dispose();
    super.dispose();
  }

  String _slug(String s) {
    final base = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return base.isEmpty ? 'field' : base;
  }

  String _uniqueFieldKey(String label) {
    final base = _slug(label);
    var key = base;
    var n = 2;
    while (_draft.fields.any((f) => f.key == key)) {
      key = '${base}_${n++}';
    }
    return key;
  }

  Future<void> _editField([FieldDef? existing]) async {
    final result = await showDialog<FieldDef>(
      context: context,
      builder: (_) => _FieldDialog(existing: existing),
    );
    if (result == null) return;
    setState(() {
      if (existing == null) {
        _draft.fields.add(FieldDef(
          key: _uniqueFieldKey(result.label),
          label: result.label,
          type: result.type,
          unit: result.unit,
        ));
      } else {
        existing
          ..label = result.label
          ..type = result.type
          ..unit = result.unit;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final store = context.read<ExerciseStore>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final name = _name.text.trim();
    final category = _category.text.trim();
    final group = _group.text.trim();

    if (!_draft.hasSets && _draft.fields.isEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nothing to log'),
          content: const Text(
              'This exercise has no sets and no fields, so only time and notes '
              'will be recorded. Save anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go back')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      );
      if (ok != true) return;
    }

    final saved = Exercise(
      id: _isNew ? store.newId(name) : _draft.id,
      name: name,
      category: category,
      group: group.isEmpty ? null : group,
      hasSets: _draft.hasSets,
      fields: _draft.fields,
      weeklyTotalField: _draft.fields.any(
              (f) => f.key == _draft.weeklyTotalField && f.type == FieldType.duration)
          ? _draft.weeklyTotalField
          : null,
      onTrackingTable: _draft.onTrackingTable,
      trackingGroup: _draft.trackingGroup,
    );
    if (_isNew) {
      await store.add(saved);
    } else {
      await store.update(saved);
    }
    messenger.showSnackBar(SnackBar(content: Text('$name saved')));
    navigator.pop();
  }

  Future<void> _delete() async {
    final store = context.read<ExerciseStore>();
    final sessions = context.read<SessionStore>();
    final navigator = Navigator.of(context);
    final count = sessions.forExercise(_draft.id).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_draft.name}?'),
        content: Text(count == 0
            ? 'It will disappear from the home screen.'
            : 'It will disappear from the home screen. Your $count logged '
                'session${count == 1 ? '' : 's'} stay saved and remain in the Google Sheet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await store.remove(_draft.id);
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExerciseStore>();
    final theme = Theme.of(context);
    final categories = store.categories;
    final groups = store.all
        .where((e) => e.category == _category.text.trim() && e.group != null)
        .map((e) => e.group!)
        .toSet()
        .toList();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'New exercise' : 'Edit exercise'),
          actions: [
            TextButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              SectionHeader('Name'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextFormField(
                  controller: _name,
                  autofocus: _isNew,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'e.g. Overhead Squat'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Give it a name' : null,
                ),
              ),
              SectionHeader('Category'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextFormField(
                  controller: _category,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Section on the home screen',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Pick or type a category' : null,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final c in {...categories, kCardio, kStrength})
                      ChoiceChip(
                        label: Text(c),
                        selected: _category.text.trim() == c,
                        onSelected: (_) => setState(() => _category.text = c),
                      ),
                  ],
                ),
              ),
              SectionHeader('Group (optional)'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextFormField(
                  controller: _group,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Collapsible folder inside the category, e.g. Pull Ups & Chin Ups',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (groups.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final g in groups)
                        ChoiceChip(
                          label: Text(g),
                          selected: _group.text.trim() == g,
                          onSelected: (sel) =>
                              setState(() => _group.text = sel ? g : ''),
                        ),
                    ],
                  ),
                ),
              SectionHeader('What to log'),
              SwitchListTile(
                title: const Text('Sets with reps and weight'),
                subtitle: const Text(
                    'Shows the set table with a warm-up checkbox and an "Add set" button'),
                value: _draft.hasSets,
                onChanged: (v) => setState(() => _draft.hasSets = v),
              ),
              SectionHeader(
                'Fields',
                trailing: TextButton.icon(
                  onPressed: () => _editField(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add field'),
                ),
              ),
              if (_draft.fields.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'No extra fields. Fields are single values logged once per workout, '
                    'like "Zone 2 time" or "Cycles".',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: _draft.fields.length,
                  onReorderItem: (from, to) => setState(() {
                    final f = _draft.fields.removeAt(from);
                    _draft.fields.insert(to, f);
                  }),
                  itemBuilder: (ctx, i) {
                    final f = _draft.fields[i];
                    return ListTile(
                      key: ValueKey(f.key),
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle),
                      ),
                      title: Text(f.label),
                      subtitle: Text(f.isDuration
                          ? 'Time · ${f.entersSeconds ? 'seconds' : 'minutes'}'
                          : '${f.type.label}${f.unit.isEmpty ? '' : ' · ${f.unit}'}'),
                      trailing: IconButton(
                        tooltip: 'Remove field',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _draft.fields.removeAt(i)),
                      ),
                      onTap: () => _editField(f),
                    );
                  },
                ),
              SectionHeader('Tracking table'),
              SwitchListTile(
                title: const Text('Show on the tracking table'),
                value: _draft.onTrackingTable,
                onChanged: (v) => setState(() => _draft.onTrackingTable = v),
              ),
              if (_draft.onTrackingTable &&
                  _draft.fields.any((f) => f.type == FieldType.duration)) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<String?>(
                    initialValue: _draft.fields.any((f) =>
                            f.key == _draft.weeklyTotalField && f.type == FieldType.duration)
                        ? _draft.weeklyTotalField
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'What the row shows'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('Days since last session')),
                      for (final f in _draft.fields.where((f) => f.type == FieldType.duration))
                        DropdownMenuItem<String?>(
                            value: f.key, child: Text('Total ${f.label} over the past 7 days')),
                    ],
                    onChanged: (v) => setState(() => _draft.weeklyTotalField = v),
                  ),
                ),
              ],
              if (!_isNew) ...[
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error),
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete exercise'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldDialog extends StatefulWidget {
  const _FieldDialog({this.existing});
  final FieldDef? existing;

  @override
  State<_FieldDialog> createState() => _FieldDialogState();
}

const String _kOtherUnit = '__other__';

class _FieldDialogState extends State<_FieldDialog> {
  late final TextEditingController _label;
  late final TextEditingController _customUnit;
  late FieldType _type;

  /// Selected preset, or [_kOtherUnit] when typing a custom one.
  late String _unitChoice;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _label = TextEditingController(text: e?.label ?? '');
    _type = e?.type ?? FieldType.number;
    final unit = e?.unit ?? '';
    final presets = _type == FieldType.duration ? timeUnits : numberUnits;
    final isPreset = presets.any((u) => u.value == unit);
    _unitChoice = e == null
        ? (_type == FieldType.duration ? 'min' : '')
        : isPreset
            ? unit
            : _kOtherUnit;
    _customUnit = TextEditingController(text: isPreset ? '' : unit);
  }

  @override
  void dispose() {
    _label.dispose();
    _customUnit.dispose();
    super.dispose();
  }

  void _setType(FieldType t) {
    setState(() {
      _type = t;
      // Keep the choice if it's valid for the new type, else reset.
      final presets = t == FieldType.duration ? timeUnits : numberUnits;
      if (!presets.any((u) => u.value == _unitChoice) && _unitChoice != _kOtherUnit) {
        _unitChoice = t == FieldType.duration ? 'min' : '';
      }
      if (t == FieldType.duration && _unitChoice == _kOtherUnit) _unitChoice = 'min';
    });
  }

  String get _unit {
    if (_type == FieldType.text) return '';
    if (_unitChoice == _kOtherUnit) return _customUnit.text.trim();
    return _unitChoice;
  }

  @override
  Widget build(BuildContext context) {
    final isTime = _type == FieldType.duration;
    final presets = isTime ? timeUnits : numberUnits;
    return AlertDialog(
      title: Text(widget.existing == null ? 'New field' : 'Edit field'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _label,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Label', hintText: 'e.g. Zone 5 time'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<FieldType>(
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final t in FieldType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (t) => _setType(t ?? _type),
            ),
            if (_type != FieldType.text) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('unit-${_type.name}'),
                initialValue: _unitChoice,
                isExpanded: true,
                decoration: InputDecoration(labelText: isTime ? 'Entered in' : 'Unit'),
                items: [
                  for (final u in presets)
                    DropdownMenuItem(value: u.value, child: Text(u.label)),
                  if (!isTime)
                    const DropdownMenuItem(value: _kOtherUnit, child: Text('Other…')),
                ],
                onChanged: (v) => setState(() => _unitChoice = v ?? _unitChoice),
              ),
              if (!isTime && _unitChoice == _kOtherUnit) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _customUnit,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Custom unit', hintText: 'e.g. laps'),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final label = _label.text.trim();
            if (label.isEmpty) return;
            Navigator.pop(
              context,
              FieldDef(
                key: widget.existing?.key ?? '',
                label: label,
                type: _type,
                unit: _unit,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
