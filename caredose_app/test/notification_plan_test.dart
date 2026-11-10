import 'package:caredose/models/models.dart';
import 'package:caredose/services/notification_plan.dart';
import 'package:flutter_test/flutter_test.dart';

Med med(String id, List<String> times, {String start = '2026-11-01', String end = '', String name = 'ยา', String meal = ''}) =>
    Med(id: id, name: name, dosage: '1 เม็ด', meal: meal, times: times, start: start, end: end);

AppData data(List<Med> meds, {bool repeat = true, bool notify = true, Map<String, DoseLog> logs = const {}}) =>
    AppData(meds: meds, repeatReminder: repeat, notify: notify, logs: logs);

void main() {
  final now = DateTime(2026, 11, 4, 8, 0, 10);

  test('dose that just passed is not scheduled but later days are', () {
    final plan = planNotifications(data([med('1', ['08:00'])], repeat: false), {}, now);
    expect(plan.any((p) => p.at == DateTime(2026, 11, 4, 8)), false);
    expect(plan.first.at, DateTime(2026, 11, 5, 8));
  });

  test('repeat reminder of a just-passed dose is still scheduled', () {
    final plan = planNotifications(data([med('1', ['08:00'])]), {}, now);
    final repeat = plan.firstWhere((p) => p.isRepeat);
    expect(repeat.at, DateTime(2026, 11, 4, 8, 15));
    expect(repeat.payload, '1|2026-11-04|08:00');
  });

  test('med starting tomorrow has nothing today; ended med has nothing', () {
    final future = planNotifications(data([med('1', ['09:00'], start: '2026-11-05')], repeat: false), {}, now);
    expect(future.first.at, DateTime(2026, 11, 5, 9));
    final ended = planNotifications(data([med('1', ['09:00'], end: '2026-11-03')]), {}, now);
    expect(ended, isEmpty);
  });

  test('notify off gives empty plan', () {
    expect(planNotifications(data([med('1', ['09:00'])], notify: false), {}, now), isEmpty);
  });

  test('logged dose has no main or repeat notification', () {
    final d = data([med('1', ['09:00'])], logs: {'1|2026-11-04|09:00': const DoseLog('taken', 'x')});
    final plan = planNotifications(d, {}, now);
    expect(plan.any((p) => p.payload == '1|2026-11-04|09:00'), false);
    expect(plan.any((p) => p.payload == '1|2026-11-05|09:00'), true);
  });

  test('repeat disabled gives no repeat entries', () {
    final plan = planNotifications(data([med('1', ['09:00'])], repeat: false), {}, now);
    expect(plan.any((p) => p.isRepeat), false);
  });

  test('dismissed key loses its repeat but not later days', () {
    final plan = planNotifications(data([med('1', ['09:00'])]), {'1|2026-11-04|09:00'}, now);
    expect(plan.any((p) => p.isRepeat && p.payload == '1|2026-11-04|09:00'), false);
    expect(plan.any((p) => !p.isRepeat && p.payload == '1|2026-11-04|09:00'), true);
    expect(plan.any((p) => p.isRepeat && p.payload == '1|2026-11-05|09:00'), true);
  });

  test('capped at 60 entries sorted by time', () {
    final plan = planNotifications(data([med('1', ['06:00', '10:00', '14:00', '20:00'])]), {}, now);
    expect(plan.length, 60);
    for (var i = 1; i < plan.length; i++) {
      expect(plan[i].at.isBefore(plan[i - 1].at), false);
    }
  });

  test('window is 14 days', () {
    final plan = planNotifications(data([med('1', ['09:00'])], repeat: false), {}, now);
    expect(plan.length, 14);
    expect(plan.last.at, DateTime(2026, 11, 17, 9));
  });

  test('two meds at same time get distinct ids; ids are stable', () {
    final plan = planNotifications(data([med('1', ['09:00']), med('2', ['09:00'])]), {}, now);
    expect(plan.map((p) => p.id).toSet().length, plan.length);
    const k = '1|2026-11-04|09:00';
    expect(notificationId(k, repeat: false), notificationId(k, repeat: false));
    expect(notificationId(k, repeat: false), isNot(notificationId(k, repeat: true)));
    expect(notificationId(k, repeat: true) <= 0x7fffffff, true);
  });

  test('title and body', () {
    final plan = planNotifications(
        data([med('1', ['09:00'], name: 'ยาลดความดัน', meal: 'หลังอาหาร')]), {}, now);
    final main = plan.firstWhere((p) => !p.isRepeat);
    expect(main.title, 'ถึงเวลาทานยา');
    expect(main.body, 'ยาลดความดัน 1 เม็ด • หลังอาหาร');
    expect(plan.firstWhere((p) => p.isRepeat).title, 'เตือนอีกครั้ง: ยังไม่ได้ทานยา');
  });

  test('a Monday-only med is planned on Mondays only', () {
    final m = Med(id: '1', name: 'ยา', dosage: '1', times: const ['09:00'], start: '2026-11-01', days: const [1]);
    final plan = planNotifications(data([m], repeat: false), {}, now);
    expect(plan.map((p) => p.at), [DateTime(2026, 11, 9, 9), DateTime(2026, 11, 16, 9)]);
  });

  test('an every-3-days med is planned on due days only', () {
    final m = Med(id: '1', name: 'ยา', dosage: '1', times: const ['09:00'], start: '2026-11-04', intervalDays: 3);
    final plan = planNotifications(data([m], repeat: false), {}, now);
    expect(plan.map((p) => p.at.day), [4, 7, 10, 13, 16]);
  });
}
