import '../models/exercise.dart';

const String kCardio = 'Cardio';
const String kStrength = 'Strength Training';
const String kOther = 'Other';

/// Bump when [defaultExercises] gains entries, and list them in
/// [exercisesAddedInVersion] so existing installs pick them up.
const int kDefaultsVersion = 5;

const String kChinCurlGroup = 'Chin Ups & Bicep Curls';

/// Exercises added to the defaults after first release, keyed by the
/// defaults version that introduced them. Applied once per install.
Map<int, List<Exercise>> exercisesAddedInVersion() => {
      2: [_other()],
    };

/// In-place changes to existing exercises, keyed by the defaults version
/// that introduced them. Each runs once per install.
Map<int, void Function(Exercise)> exerciseUpdatesInVersion() => {
      // v3: the tracking table shows Zone 2 as minutes per week.
      3: (e) {
        if (e.id == 'zone2_cardio' && e.weeklyTotalField == null &&
            e.fields.any((f) => f.key == 'zone2_time')) {
          e.weeklyTotalField = 'zone2_time';
        }
      },
      // v4: "Other" is a catch-all, so it has no row on the tracking table.
      4: (e) {
        if (e.id == 'other') e.onTrackingTable = false;
      },
      // v5: chin ups and bicep curls share one tracking row.
      5: (e) {
        if ((e.id == 'chin_ups' || e.id == 'bicep_curls') && e.trackingGroup == null) {
          e.trackingGroup = kChinCurlGroup;
        }
      },
    };

/// A catch-all: just the clock and a notes field.
Exercise _other() =>
    Exercise(id: 'other', name: 'Other', category: kOther, onTrackingTable: false);

FieldDef _duration(String key, String label) =>
    FieldDef(key: key, label: label, type: FieldType.duration);

Exercise _strength(String id, String name, {String? group, String? trackingGroup}) =>
    Exercise(id: id, name: name, category: kStrength, group: group, hasSets: true,
        trackingGroup: trackingGroup);

/// The exercises the app ships with. Copied into the editable exercise store
/// on first launch; after that the store is the source of truth.
List<Exercise> defaultExercises() => [
      Exercise(
        id: 'cardio_intervals',
        name: 'Cardio Interval Training',
        category: kCardio,
        fields: [
          _duration('ramp_up_time', 'Ramp up time'),
          _duration('work_time', 'Stable intense work time'),
          _duration('easy_time', 'Less intense time'),
          FieldDef(key: 'ramp_up_mph', label: 'Ramp up speed', unit: 'mph'),
          FieldDef(key: 'stable_mph', label: 'Stable speed', unit: 'mph'),
          FieldDef(key: 'cycles', label: 'Cycles', type: FieldType.integer),
          _duration('zone5_time', 'Zone 5 time'),
        ],
      ),
      Exercise(
        id: 'zone2_cardio',
        name: 'Zone 2 Cardio',
        category: kCardio,
        fields: [_duration('zone2_time', 'Zone 2 time')],
        weeklyTotalField: 'zone2_time',
      ),
      _strength('squats', 'Squats'),
      _strength('deadlifts', 'Deadlifts'),
      _strength('bench_press', 'Bench Press'),
      _strength('shoulder_press', 'Shoulder Press'),
      _strength('bent_over_rows', 'Bent Over Rows'),
      _strength('pull_ups', 'Pull Ups', group: 'Pull Ups & Chin Ups'),
      _strength('chin_ups', 'Chin Ups', group: 'Pull Ups & Chin Ups', trackingGroup: kChinCurlGroup),
      _strength('bicep_curls', 'Bicep Curls', trackingGroup: kChinCurlGroup),
      _other(),
    ];
