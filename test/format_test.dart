import 'package:exercise_tracker/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMinutesToSeconds', () {
    test('decimal minutes', () {
      expect(parseMinutesToSeconds('1.5'), 90);
      expect(parseMinutesToSeconds('45'), 2700);
      expect(parseMinutesToSeconds(' 0.25 '), 15);
    });
    test('m:ss', () {
      expect(parseMinutesToSeconds('1:30'), 90);
      expect(parseMinutesToSeconds('12:05'), 725);
    });
    test('rejects junk', () {
      expect(parseMinutesToSeconds(''), isNull);
      expect(parseMinutesToSeconds('abc'), isNull);
      expect(parseMinutesToSeconds('1:75'), isNull);
      expect(parseMinutesToSeconds('-3'), isNull);
    });
  });

  test('fmtClock', () {
    expect(fmtClock(0), '0:00');
    expect(fmtClock(90), '1:30');
    expect(fmtClock(3725), '1:02:05');
  });

  test('fmtDurationWords', () {
    expect(fmtDurationWords(42), '42 sec');
    expect(fmtDurationWords(1380), '23 min');
    expect(fmtDurationWords(3600), '1 hr');
    expect(fmtDurationWords(3900), '1 hr 5 min');
  });

  test('weight formatting and conversion round-trips cleanly', () {
    expect(fmtNumber(135.0), '135');
    expect(fmtNumber(62.5), '62.5');
    expect(fmtWeight(135, 'lb', 'lb'), '135 lb');
    expect(fmtWeight(135, 'lb', 'kg'), '61.2 kg');
    expect(fmtWeight(100, 'kg', 'lb'), '220.5 lb');
    final kg = convertWeight(135, 'lb', 'kg');
    expect(fmtNumber(convertWeight(kg, 'kg', 'lb')), '135');
  });

  test('days since', () {
    final now = DateTime(2026, 11, 3, 9);
    expect(calendarDaysBetween(DateTime(2026, 11, 3, 23), now), 0);
    expect(calendarDaysBetween(DateTime(2026, 11, 2, 23, 59), now), 1);
    expect(calendarDaysBetween(DateTime(2026, 10, 28), now), 6);
    expect(fmtDaysSince(null), 'Never');
    expect(fmtDaysSince(0), 'Today');
    expect(fmtDaysSince(1), 'Yesterday');
    expect(fmtDaysSince(6), '6 days');
    expect(fmtDaysSince(30), '30 days');
    expect(fmtDaysSince(31), 'More than a month');
  });
}
