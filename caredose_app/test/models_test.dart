import 'package:caredose/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 4, 10, 0);

  test('seed round-trips through JSON', () {
    final a = AppData.seed(now);
    final b = AppData.fromJson(a.toJson());
    expect(b.toJson(), a.toJson());
  });

  test('seed matches web sample data', () {
    final d = AppData.seed(now);
    expect(d.patient, 'คุณแม่สมศรี');
    expect(d.meds.map((m) => m.id), ['m1', 'm2', 'm3']);
    expect(d.meds[1].times, ['08:00', '18:00']);
    expect(d.meds[0].start, '2026-11-04');
    expect(d.appts.single.at, '2026-11-09T09:30');
    expect(d.verifiedPhone, '081-234-5678');
    expect(d.repeatReminder, true);
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
