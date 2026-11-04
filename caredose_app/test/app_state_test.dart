import 'package:caredose/logic/dose_items.dart';
import 'package:caredose/models/models.dart';
import 'package:caredose/services/storage.dart';
import 'package:caredose/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeScheduler implements NotificationScheduler {
  int calls = 0;
  AppData? last;
  DateTime? lastNow;
  @override
  Future<void> reschedule(AppData d, Set<String> dismissed, DateTime now) async {
    calls++;
    last = d;
    lastNow = now;
  }
}

const date = '2026-11-04';

Future<(AppState, FakeScheduler, Storage)> make({DateTime Function()? clock}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = Storage(await SharedPreferences.getInstance());
  final sched = FakeScheduler();
  final s = AppState(storage, sched, clock: clock ?? () => DateTime(2026, 11, 4, 9));
  return (s, sched, storage);
}

void main() {
  test('mark taken logs, persists and reschedules', () async {
    final (s, sched, storage) = await make();
    final it = itemsFor(s.data, date, s.now).first;
    s.mark(it, DoseStatus.taken);
    await s.flush();
    expect(s.data.logs[it.key]?.status, 'taken');
    expect(storage.load(s.now).logs[it.key]?.status, 'taken');
    expect(sched.calls, 1);
  });

  test('undo removes the log', () async {
    final (s, _, _) = await make();
    final it = itemsFor(s.data, date, s.now).first;
    s.mark(it, DoseStatus.skipped);
    expect(s.data.logs[it.key]?.status, 'skipped');
    s.undo(it);
    expect(s.data.logs.containsKey(it.key), false);
  });

  test('markMeal logs only due items without a log; undoKeys reverts', () async {
    final (s, _, _) = await make();
    final all = itemsFor(s.data, date, s.now);
    final due = all.where((i) => i.time == '08:00').toList();
    final evening = all.firstWhere((i) => i.time == '18:00');
    s.mark(due.first, DoseStatus.taken);
    final keys = s.markMeal([...itemsFor(s.data, date, s.now).where((i) => i.time == '08:00'), evening]);
    expect(keys, [due.last.key]);
    expect(s.data.logs.containsKey(evening.key), false);
    s.undoKeys(keys);
    expect(s.data.logs.containsKey(due.last.key), false);
    expect(s.data.logs.containsKey(due.first.key), true);
  });

  test('saveMed adds new and replaces existing', () async {
    final (s, _, _) = await make();
    s.saveMed(const Med(id: 'new', name: 'x', times: ['07:00']));
    expect(s.data.meds.length, 4);
    s.saveMed(const Med(id: 'new', name: 'y', times: ['07:00']));
    expect(s.data.meds.length, 4);
    expect(s.data.meds.last.name, 'y');
  });

  test('relatives save and delete', () async {
    final (s, _, _) = await make();
    s.saveRelative(const Relative(id: 'r2', name: 'a', phone: '1'));
    expect(s.data.relatives.length, 2);
    s.deleteRelative('r2');
    expect(s.data.relatives.map((r) => r.id), ['r1']);
  });

  test('addBmi puts newest first', () async {
    final (s, _, _) = await make();
    s.addBmi(58, 155);
    expect(s.data.bmis.first.v, 24.1);
    expect(s.data.bmis.first.cat, 'ปกติ');
  });

  test('setters update settings and reschedule', () async {
    final (s, sched, _) = await make();
    s.setNotify(false);
    s.setSize('xl');
    s.setRepeat(false);
    s.setChannel('sms');
    s.setPatient('ก');
    s.setVerifiedPhone('0899999999');
    await s.flush();
    expect(s.data.notify, false);
    expect(s.data.size, 'xl');
    expect(s.data.repeatReminder, false);
    expect(s.data.notifyChannel, 'sms');
    expect(s.data.patient, 'ก');
    expect(s.data.verifiedPhone, '0899999999');
    expect(sched.calls, 6);
  });

  test('resetAll restores seed and clears dismissed', () async {
    final (s, _, _) = await make();
    s.setPatient('ก');
    s.dismissed.add('k');
    await s.resetAll();
    expect(s.data.toJson(), AppData.seed(s.now).toJson());
    expect(s.dismissed, isEmpty);
  });

  test('applyNotificationAction taken logs; notyet dismisses without log', () async {
    final (s, sched, _) = await make();
    const key = 'm1|2026-11-04|08:00';
    await s.applyNotificationAction('notyet', key);
    expect(s.data.logs.containsKey(key), false);
    expect(s.dismissed, {key});
    await s.applyNotificationAction('taken', key);
    expect(s.data.logs[key]?.status, 'taken');
    expect(sched.calls, 2);
  });

  test('reload without disk changes does not reschedule', () async {
    final (s, sched, _) = await make();
    await s.reload();
    await s.reload();
    expect(sched.calls, 0);
  });

  test('tick refreshes now from the clock', () async {
    var t = DateTime(2026, 11, 4, 9);
    final (s, _, _) = await make(clock: () => t);
    t = DateTime(2026, 11, 4, 9, 30);
    s.tick();
    expect(s.now, DateTime(2026, 11, 4, 9, 30));
  });

  const key = 'm1|2026-11-04|08:00';

  test('button pressed in background is not overwritten by a later in-app edit', () async {
    final (s, _, storage) = await make();
    await storage.appendPending('taken\t$key\t2026-11-04T09:00:00.000');
    s.setPatient('แก้ในแอป');
    await s.flush();
    expect(s.data.logs[key]?.status, 'taken');
    expect(storage.load(s.now).logs[key]?.status, 'taken');
    expect(storage.loadPending(), isEmpty);
  });

  test('notyet from background survives later edits so the repeat is not recreated', () async {
    final (s, _, storage) = await make();
    await storage.appendPending('notyet\t$key\t2026-11-04T09:00:00.000');
    s.setPatient('x');
    await s.flush();
    expect(s.dismissed, {key});
    expect(storage.loadDismissed(), {key});
    expect(s.data.logs.containsKey(key), false);
  });

  test('reload applies pending background actions and reschedules once', () async {
    final (s, sched, storage) = await make();
    await storage.appendPending('skip\t$key\t2026-11-04T09:00:00.000');
    await s.reload();
    expect(s.data.logs[key]?.status, 'skipped');
    expect(sched.calls, 1);
    await s.reload();
    expect(sched.calls, 1);
  });

  test('reschedule uses the clock at persist time, not a stale now', () async {
    var t = DateTime(2026, 11, 4, 9);
    final (s, sched, _) = await make(clock: () => t);
    t = DateTime(2026, 11, 4, 9, 0, 30);
    s.setPatient('x');
    await s.flush();
    expect(sched.lastNow, DateTime(2026, 11, 4, 9, 0, 30));
  });
}
