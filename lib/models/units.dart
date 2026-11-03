/// Unit choices offered when defining a field. Any other unit can still be
/// typed in as "Other".
class UnitOption {
  const UnitOption(this.value, this.label);
  final String value;
  final String label;
}

/// How a time field is entered. Always stored in seconds.
const List<UnitOption> timeUnits = [
  UnitOption('sec', 'Seconds'),
  UnitOption('min', 'Minutes'),
];

/// Units for number fields. The empty value means no unit.
const List<UnitOption> numberUnits = [
  UnitOption('', 'None'),
  UnitOption('mph', 'mph'),
  UnitOption('km/h', 'km/h'),
  UnitOption('min/km', 'min/km (pace)'),
  UnitOption('min/mi', 'min/mile (pace)'),
  UnitOption('lb', 'lb'),
  UnitOption('kg', 'kg'),
  UnitOption('bpm', 'bpm'),
  UnitOption('m', 'metres'),
  UnitOption('km', 'km'),
  UnitOption('mi', 'miles'),
  UnitOption('ft', 'feet'),
  UnitOption('floors', 'floors'),
  UnitOption('cal', 'calories'),
  UnitOption('%', '%'),
];
