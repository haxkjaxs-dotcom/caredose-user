import 'package:caredose/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers.dart';

void main() {
  final now = DateTime(2026, 11, 4, 10, 0);

  test('seed round-trips through JSON', () {
    final a = AppData.seed(now);
    final b = AppData.fromJson(a.toJson());
    expect(b.toJson(), a.toJson());
  });

  test('seed is empty defaults', () {
    final d = AppData.seed(now);
    expect(d.patient, '');
    expect(d.size, 'normal');
    expect(d.notify, true);
    expect(d.notifyChannel, 'app');
    expect(d.repeatReminder, true);
    expect(d.verifiedPhone, '');
    expect([d.meds, d.doctors, d.relatives, d.appts, d.bmis], everyElement(isEmpty));
    expect(d.logs, isEmpty);
    expect(d.scheduleIds, isEmpty);
  });

  test('scheduleIds round-trip through JSON and survive copyWith', () {
    final d = AppData.seed(now).copyWith(scheduleIds: {'p1|08:00': 's1'});
    expect(AppData.fromJson(d.toJson()).scheduleIds, {'p1|08:00': 's1'});
    expect(d.copyWith(patient: 'x').scheduleIds, {'p1|08:00': 's1'});
    expect(AppData.fromJson({'scheduleIds': {'a': 1, 'b': 'c'}}).scheduleIds, {'b': 'c'});
  });

  test('sample fixture matches the old web sample data', () {
    final d = sampleData(now);
    expect(d.meds.map((m) => m.id), ['m1', 'm2', 'm3']);
    expect(d.meds[1].times, ['08:00', '18:00']);
  });

  test('med missing times and wrong types do not throw', () {
    final m = Med.fromJson({'id': 'x', 'name': 5});
    expect(m.times, <String>[]);
    expect(m.name, '');
    expect(m.id, 'x');
  });

  test('malformed times and dates are dropped instead of crashing later', () {
    final m = Med.fromJson({
      'id': 'x',
      'name': 'a',
      'times': ['8:00', '08:00', '24:00', 'x', '12:60', '23:59'],
      'start': 'x',
      'end': '2026-13-45',
    });
    expect(m.times, ['08:00', '23:59']);
    expect(m.start, '');
    expect(m.end, '');
    expect(Med.fromJson({'start': '2026-11-04', 'end': '2026-12-01'}).end, '2026-12-01');
  });

  test('appt omits null optional fields in JSON', () {
    final a = Appt(id: 'a', at: '2026-11-09T09:30', place: 'p', dept: '', note: '');
    expect(a.toJson().containsKey('status'), false);
  });
}
