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
}
