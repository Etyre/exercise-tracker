/// How a per-session field is entered and displayed.
enum FieldType {
  /// Decimal number, e.g. speed in mph.
  number,

  /// Whole number, e.g. cycles.
  integer,

  /// Entered in minutes (decimal or m:ss), stored in seconds.
  duration,

  /// Free text.
  text,
}

extension FieldTypeLabel on FieldType {
  String get label => switch (this) {
        FieldType.number => 'Number',
        FieldType.integer => 'Whole number',
        FieldType.duration => 'Time (minutes)',
        FieldType.text => 'Text',
      };
}

/// One per-session input field on an exercise's logging screen.
class FieldDef {
  FieldDef({
    required this.key,
    required this.label,
    this.type = FieldType.number,
    this.unit = '',
  });

  /// Stable identifier, kept when the label is edited.
  final String key;
  String label;
  FieldType type;

  /// Shown after the input, e.g. "mph". Ignored for duration/text.
  String unit;

  FieldDef copy() => FieldDef(key: key, label: label, type: type, unit: unit);

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type.name,
        'unit': unit,
      };

  factory FieldDef.fromJson(Map<String, dynamic> j) => FieldDef(
        key: j['key'] as String,
        label: (j['label'] as String?) ?? j['key'] as String,
        type: FieldType.values.firstWhere((t) => t.name == j['type'],
            orElse: () => FieldType.number),
        unit: (j['unit'] as String?) ?? '',
      );
}

/// A kind of exercise: what it's called, where it sits on the home screen,
/// and what gets logged for it.
class Exercise {
  Exercise({
    required this.id,
    required this.name,
    required this.category,
    this.group,
    this.hasSets = false,
    List<FieldDef>? fields,
    this.weeklyTotalField,
    this.onTrackingTable = true,
    this.trackingGroup,
  }) : fields = fields ?? [];

  /// Stable identifier stored with every session. Never changes.
  final String id;
  String name;

  /// Section on the home screen, e.g. "Cardio" or "Strength Training".
  String category;

  /// Optional collapsible sub-group within the category.
  String? group;

  /// Whether the logging screen shows the reps / weight / warm-up set table.
  bool hasSets;

  /// Per-session fields shown below the set table (if any).
  List<FieldDef> fields;

  /// Key of a duration field. When set, the tracking table shows this
  /// field's total over the past 7 days instead of days since the last
  /// session (e.g. Zone 2 minutes per week).
  String? weeklyTotalField;

  /// Whether this exercise has a row on the tracking table.
  bool onTrackingTable;

  /// Exercises sharing a tracking group name share one row on the tracking
  /// table, e.g. "Chin Ups & Bicep Curls": days since either was last done.
  String? trackingGroup;

  Exercise copy() => Exercise(
        id: id,
        name: name,
        category: category,
        group: group,
        hasSets: hasSets,
        fields: fields.map((f) => f.copy()).toList(),
        weeklyTotalField: weeklyTotalField,
        onTrackingTable: onTrackingTable,
        trackingGroup: trackingGroup,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'group': group,
        'hasSets': hasSets,
        'fields': fields.map((f) => f.toJson()).toList(),
        'weeklyTotalField': weeklyTotalField,
        'onTrackingTable': onTrackingTable,
        'trackingGroup': trackingGroup,
      };

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        category: (j['category'] as String?) ?? 'Other',
        group: (j['group'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['group'] as String).trim(),
        hasSets: j['hasSets'] == true,
        fields: ((j['fields'] as List?) ?? const [])
            .map((f) => FieldDef.fromJson(Map<String, dynamic>.from(f as Map)))
            .toList(),
        weeklyTotalField: (j['weeklyTotalField'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['weeklyTotalField'] as String).trim(),
        onTrackingTable: j['onTrackingTable'] != false,
        trackingGroup: (j['trackingGroup'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['trackingGroup'] as String).trim(),
      );
}
