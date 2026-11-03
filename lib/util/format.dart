import 'package:intl/intl.dart';

const double kgPerLb = 0.45359237;

/// Convert a weight between 'lb' and 'kg'.
double convertWeight(double value, String from, String to) {
  if (from == to) return value;
  return from == 'lb' ? value * kgPerLb : value / kgPerLb;
}

/// Format a weight without a trailing ".0" and with at most one decimal.
String fmtNumber(double value) {
  final rounded = (value * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
  return rounded.toStringAsFixed(1);
}

/// Weight as entered in [set.unit], shown in [displayUnit].
String fmtWeight(double value, String fromUnit, String displayUnit) =>
    '${fmtNumber(convertWeight(value, fromUnit, displayUnit))} $displayUnit';

/// Parse a minutes value typed by the user into whole seconds.
///
/// Accepts decimal minutes ("1.5" -> 90) and "m:ss" ("1:30" -> 90).
/// Returns null for blank or unparseable input.
int? parseMinutesToSeconds(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (s.contains(':')) {
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final m = int.tryParse(parts[0].trim());
    final sec = int.tryParse(parts[1].trim());
    if (m == null || sec == null || sec < 0 || sec >= 60) return null;
    return m * 60 + sec;
  }
  final minutes = double.tryParse(s);
  if (minutes == null || minutes < 0) return null;
  return (minutes * 60).round();
}

/// Seconds back to the minutes text shown in an input field.
String secondsToMinutesText(int? seconds) {
  if (seconds == null) return '';
  return fmtNumber(seconds / 60);
}

/// "m:ss" or "h:mm:ss".
String fmtClock(int totalSeconds) {
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Human-friendly duration: "45 sec", "12 min", "1 hr 5 min".
String fmtDurationWords(int totalSeconds) {
  if (totalSeconds < 60) return '$totalSeconds sec';
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h hr' : '$h hr $m min';
}

final _dateTimeFmt = DateFormat('EEE, MMM d, y · h:mm a');
final _dateFmt = DateFormat('EEE, MMM d');
final _timeFmt = DateFormat('h:mm a');

String fmtDateTime(DateTime d) => _dateTimeFmt.format(d);
String fmtDate(DateTime d) => _dateFmt.format(d);
String fmtTime(DateTime d) => _timeFmt.format(d);

/// Whole calendar days from [from] to [to], ignoring time of day.
int calendarDaysBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// "Today", "Yesterday", "6 days", "More than a month", or "Never".
String fmtDaysSince(int? days) {
  if (days == null) return 'Never';
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days > 30) return 'More than a month';
  return '$days days';
}

/// Seconds of [fieldKey] logged in sessions that started within the last
/// 7 days (a rolling week ending now).
int weeklyTotalSeconds(Iterable<dynamic> sessions, String fieldKey, DateTime now) {
  final since = now.subtract(const Duration(days: 7));
  var total = 0;
  for (final s in sessions) {
    if ((s.startedAt as DateTime).isBefore(since)) continue;
    for (final f in s.fields) {
      if (f.key == fieldKey && f.value is num) total += (f.value as num).round();
    }
  }
  return total;
}
