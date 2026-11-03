import 'exercise.dart';

/// One logged set of a strength exercise.
class StrengthSet {
  StrengthSet({
    this.reps,
    this.weight,
    this.unit = 'lb',
    this.warmup = false,
  });

  int? reps;
  double? weight;

  /// Unit the weight was *entered* in ('lb' or 'kg'). Kept per set so the
  /// number you typed is what gets stored, even if you flip the unit later.
  String unit;
  bool warmup;

  bool get isEmpty => reps == null && weight == null;

  Map<String, dynamic> toJson() => {
        'reps': reps,
        'weight': weight,
        'unit': unit,
        'warmup': warmup,
      };

  factory StrengthSet.fromJson(Map<String, dynamic> j) => StrengthSet(
        reps: (j['reps'] as num?)?.toInt(),
        weight: (j['weight'] as num?)?.toDouble(),
        unit: (j['unit'] as String?) ?? 'lb',
        warmup: j['warmup'] == true,
      );
}

/// A value logged for one of the exercise's per-session fields. The label,
/// type and unit are snapshotted so history still reads correctly if the
/// exercise definition is edited later.
class FieldValue {
  FieldValue({
    required this.key,
    required this.label,
    required this.type,
    this.unit = '',
    this.value,
  });

  final String key;
  final String label;
  final FieldType type;
  final String unit;

  /// num for number/integer, int seconds for duration, String for text.
  final Object? value;

  factory FieldValue.of(FieldDef def, Object? value) => FieldValue(
        key: def.key,
        label: def.label,
        type: def.type,
        unit: def.unit,
        value: value,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type.name,
        'unit': unit,
        'value': value,
      };

  factory FieldValue.fromJson(Map<String, dynamic> j) => FieldValue(
        key: j['key'] as String,
        label: (j['label'] as String?) ?? j['key'] as String,
        type: FieldType.values.firstWhere((t) => t.name == j['type'],
            orElse: () => FieldType.number),
        unit: (j['unit'] as String?) ?? '',
        value: j['value'],
      );
}

/// One completed visit to an exercise screen, from open to submit.
class WorkoutSession {
  WorkoutSession({
    required this.id,
    required this.exerciseId,
    required this.exerciseName,
    required this.category,
    required this.startedAt,
    required this.finishedAt,
    this.notes = '',
    List<StrengthSet>? sets,
    List<FieldValue>? fields,
    this.synced = false,
  })  : sets = sets ?? [],
        fields = fields ?? [];

  final String id;
  final String exerciseId;

  /// Snapshotted at save time so history survives renames and deletions.
  final String exerciseName;
  final String category;

  final DateTime startedAt;
  final DateTime finishedAt;
  String notes;
  List<StrengthSet> sets;
  List<FieldValue> fields;

  /// True once this session has been written to the Google Sheet.
  bool synced;

  Duration get duration => finishedAt.difference(startedAt);
  int get durationSec => duration.inSeconds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'exerciseId': exerciseId,
        'exerciseName': exerciseName,
        'category': category,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'durationSec': durationSec,
        'notes': notes,
        'sets': sets.map((s) => s.toJson()).toList(),
        'fields': fields.map((f) => f.toJson()).toList(),
        'synced': synced,
      };

  factory WorkoutSession.fromJson(Map<String, dynamic> j) => WorkoutSession(
        id: j['id'] as String,
        exerciseId: j['exerciseId'] as String,
        exerciseName: (j['exerciseName'] as String?) ?? j['exerciseId'] as String,
        category: (j['category'] as String?) ?? '',
        startedAt: DateTime.parse(j['startedAt'] as String).toLocal(),
        finishedAt: DateTime.parse(j['finishedAt'] as String).toLocal(),
        notes: (j['notes'] as String?) ?? '',
        sets: ((j['sets'] as List?) ?? const [])
            .map((s) => StrengthSet.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList(),
        fields: ((j['fields'] as List?) ?? const [])
            .map((f) => FieldValue.fromJson(Map<String, dynamic>.from(f as Map)))
            .toList(),
        synced: j['synced'] == true,
      );
}
