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

  test('appt omits null optional fields in JSON', () {
    final a = Appt(id: 'a', at: '2026-11-09T09:30', place: 'p', dept: '', note: '');
    expect(a.toJson().containsKey('status'), false);
  });
}
