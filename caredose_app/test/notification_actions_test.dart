import 'package:caredose/models/models.dart';
import 'package:caredose/services/notification_actions.dart';
import 'package:caredose/services/notification_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 4, 9, 5);
  const key = '1|2026-11-04|09:00';
  final base = AppData(
    meds: const [Med(id: '1', name: 'ยา', dosage: '1 เม็ด', times: ['09:00'], start: '2026-11-01')],
  );

  test('taken writes a taken log', () {
    final r = applyDoseAction(base, {}, 'taken', key, now);
    expect(r.data.logs[key]?.status, 'taken');
    expect(r.data.logs[key]?.at, now.toIso8601String());
  });

  test('skip writes a skipped log', () {
    expect(applyDoseAction(base, {}, 'skip', key, now).data.logs[key]?.status, 'skipped');
  });

  test('notyet writes no log and dismisses the key', () {
    final r = applyDoseAction(base, {}, 'notyet', key, now);
    expect(r.data.logs, isEmpty);
    expect(r.dismissed, {key});
    final plan = planNotifications(r.data, r.dismissed, now);
    expect(plan.any((p) => p.isRepeat && p.payload == key), false);
  });

  test('unknown action changes nothing', () {
    final r = applyDoseAction(base, {'x|2026-11-04|09:00'}, 'weird', key, now);
    expect(r.data.logs, isEmpty);
    expect(r.dismissed, {'x|2026-11-04|09:00'});
  });

  test('old dismissed keys are pruned', () {
    final r = applyDoseAction(base, {'1|2026-10-30|09:00', '1|2026-11-03|09:00'}, 'notyet', key, now);
    expect(r.dismissed, {'1|2026-11-03|09:00', key});
  });
}
