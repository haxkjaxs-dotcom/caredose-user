import 'package:caredose/logic/dose_items.dart';
import 'package:caredose/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Med med(String id, String name, List<String> times, {String start = '2026-11-01', String end = ''}) =>
    Med(id: id, name: name, dosage: '1 เม็ด', times: times, start: start, end: end);

void main() {
  const date = '2026-11-04';

  test('items sorted by time then name', () {
    final d = AppData(meds: [med('1', 'ข', ['08:00']), med('2', 'ก', ['08:00']), med('3', 'ค', ['07:00'])]);
    final items = itemsFor(d, date, DateTime(2026, 11, 4, 6));
    expect(items.map((i) => i.med.name), ['ค', 'ก', 'ข']);
    expect(items.first.key, '3|2026-11-04|07:00');
  });

  test('med starting tomorrow or ended yesterday is excluded', () {
    final d = AppData(meds: [
      med('1', 'a', ['08:00'], start: '2026-11-05'),
      med('2', 'b', ['08:00'], end: '2026-11-03'),
      med('3', 'c', ['08:00'], end: '2026-11-04'),
    ]);
    expect(itemsFor(d, date, DateTime(2026, 11, 4, 6)).map((i) => i.med.id), ['3']);
  });

  test('status pending before and missed after the dose time', () {
    final d = AppData(meds: [med('1', 'a', ['08:00'])]);
    expect(itemsFor(d, date, DateTime(2026, 11, 4, 7)).single.status, DoseStatus.pending);
    expect(itemsFor(d, date, DateTime(2026, 11, 4, 9)).single.status, DoseStatus.missed);
  });

  test('log wins over time', () {
    final d = AppData(
      meds: [med('1', 'a', ['08:00'])],
      logs: {'1|2026-11-04|08:00': const DoseLog('taken', '2026-11-04T08:05:00')},
    );
    final it = itemsFor(d, date, DateTime(2026, 11, 4, 20)).single;
    expect(it.status, DoseStatus.taken);
    expect(it.log?.at, '2026-11-04T08:05:00');
  });

  test('skipped log gives skipped status', () {
    final d = AppData(
      meds: [med('1', 'a', ['08:00'])],
      logs: {'1|2026-11-04|08:00': const DoseLog('skipped', 'x')},
    );
    expect(itemsFor(d, date, DateTime(2026, 11, 4, 20)).single.status, DoseStatus.skipped);
  });

  test('doseTime parses date and time', () {
    expect(doseTime('2026-11-04', '08:30'), DateTime(2026, 11, 4, 8, 30));
  });

  test('status labels are Thai', () {
    expect(doseStatusLabel(DoseStatus.taken), 'ทานแล้ว');
    expect(doseStatusLabel(DoseStatus.skipped), 'ยังไม่ได้ทาน');
    expect(doseStatusLabel(DoseStatus.pending), 'รอทาน');
    expect(doseStatusLabel(DoseStatus.missed), 'เลยเวลา');
  });

  group('isDueOn', () {
    Med rule({List<int> days = const [], int interval = 0, String start = '2026-11-09', String end = ''}) =>
        Med(id: 'r', name: 'r', times: const ['08:00'], start: start, end: end, days: days, intervalDays: interval);

    test('no rule is every day, inside start/end only', () {
      expect(isDueOn(rule(), '2026-11-09'), true);
      expect(isDueOn(rule(), '2026-11-08'), false);
      expect(isDueOn(rule(end: '2026-11-10'), '2026-11-11'), false);
    });
    test('weekdays use ISO numbers: Monday 1 ... Sunday 7', () {
      final mwf = rule(days: const [1, 3, 5]);
      expect(isDueOn(mwf, '2026-11-09'), true); // Mon
      expect(isDueOn(mwf, '2026-11-10'), false); // Tue
      expect(isDueOn(mwf, '2026-11-11'), true); // Wed
      expect(isDueOn(rule(days: const [7]), '2026-11-15'), true); // Sun
      expect(isDueOn(rule(days: const [7]), '2026-11-09'), false);
    });
    test('every N days counts from start', () {
      final every2 = rule(interval: 2);
      expect(isDueOn(every2, '2026-11-09'), true);
      expect(isDueOn(every2, '2026-11-10'), false);
      expect(isDueOn(every2, '2026-11-11'), true);
      expect(isDueOn(every2, '2026-11-08'), false); // before start
    });
    test('every N days across a year and a month boundary', () {
      final y = rule(interval: 3, start: '2026-12-30');
      expect(isDueOn(y, '2026-12-31'), false);
      expect(isDueOn(y, '2027-01-01'), false);
      expect(isDueOn(y, '2027-01-02'), true);
      final m = rule(interval: 7, start: '2026-02-26');
      expect(isDueOn(m, '2026-03-05'), true);
      expect(isDueOn(m, '2026-03-04'), false);
    });
    test('interval without a start date falls back to every day', () {
      expect(isDueOn(rule(interval: 2, start: ''), '2026-11-10'), true);
    });
    test('days win when both are set', () {
      final both = rule(days: const [1], interval: 2);
      expect(isDueOn(both, '2026-11-11'), false); // Wed: interval says due, days say no
      expect(isDueOn(both, '2026-11-16'), true); // Mon
    });
  });

  test('itemsFor skips a weekday med on a day it is not due', () {
    final d = AppData(meds: [Med(id: '1', name: 'a', times: const ['08:00'], start: '2026-11-01', days: const [1])]);
    expect(itemsFor(d, '2026-11-10', DateTime(2026, 11, 10, 6)), isEmpty); // Tue
    expect(itemsFor(d, '2026-11-09', DateTime(2026, 11, 9, 6)), hasLength(1)); // Mon
  });
}
