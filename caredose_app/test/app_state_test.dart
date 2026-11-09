import 'dart:convert';

import 'package:caredose/logic/dose_items.dart';
import 'package:caredose/models/models.dart';
import 'package:caredose/models/remote_plan.dart';
import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/services/log_outbox.dart';
import 'package:caredose/services/storage.dart';
import 'package:caredose/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_med_repository.dart';
import 'helpers.dart' show sampleData;

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

Future<(AppState, FakeScheduler, Storage)> make({DateTime Function()? clock, LogOutbox? outbox}) async {
  SharedPreferences.setMockInitialValues({'caredose': jsonEncode(sampleData(DateTime(2026, 11, 4, 9)).toJson())});
  final storage = Storage(await SharedPreferences.getInstance());
  final sched = FakeScheduler();
  final s = AppState(storage, sched, clock: clock ?? () => DateTime(2026, 11, 4, 9), outbox: outbox);
  return (s, sched, storage);
}

void main() {
  applyRemoteTests();
  outboxTests();
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

  test('resetAll drops queued button presses so they cannot touch the sample data', () async {
    final (s, _, storage) = await make();
    await storage.appendPending('taken\tm1|2026-11-04|08:00\t2026-11-04T09:00:00.000');
    await s.resetAll();
    expect(storage.loadPending(), isEmpty);
    expect(s.data.logs, isEmpty);
    await s.flush();
    expect(s.data.logs, isEmpty);
  });

  test('reminders can be switched off (signed out) and back on', () async {
    final (s, sched, _) = await make();
    s.setRemindersEnabled(false);
    await s.flush();
    expect(sched.last?.notify, false); // scheduler told to plan nothing
    expect(s.data.notify, true); // the user's own setting is untouched
    await s.rescheduleNow();
    expect(sched.last?.notify, false);
    s.setPatient('x');
    await s.flush();
    expect(sched.last?.notify, false);
    s.setRemindersEnabled(true);
    await s.flush();
    expect(sched.last?.notify, true);
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

RemotePlan _plan(String id, {String time = '08:00', String sid = 's1', String name = 'ยาใหม่'}) => RemotePlan(
      id: id,
      name: name,
      dosage: '1 เม็ด',
      meal: 'หลังอาหาร',
      start: '2026-11-01',
      end: '',
      note: '',
      schedules: [PlanSchedule(sid, time)],
    );

void applyRemoteTests() {
  group('applyRemote', () {
    test('replaces meds, builds scheduleIds, reschedules once; same data again does nothing', () async {
      final (s, sched, storage) = await make();
      s.applyRemote(plans: [_plan('p1')], logs: const []);
      await s.flush();
      expect(s.data.meds.map((m) => m.id), ['p1']);
      expect(s.data.meds.single.times, ['08:00']);
      expect(s.data.scheduleIds, {'p1|08:00': 's1'});
      expect(storage.load(s.now).meds.single.id, 'p1');
      expect(sched.calls, 1);
      var notified = 0;
      s.addListener(() => notified++);
      s.applyRemote(plans: [_plan('p1')], logs: const []);
      await s.flush();
      expect(sched.calls, 1);
      expect(notified, 0);
    });

    test('a plan missing from the server disappears and the notifications are rebuilt', () async {
      final (s, sched, _) = await make();
      s.applyRemote(plans: [_plan('p1'), _plan('p2', sid: 's2')], logs: const []);
      await s.flush();
      s.applyRemote(plans: [_plan('p1')], logs: const []);
      await s.flush();
      expect(s.data.meds.map((m) => m.id), ['p1']);
      expect(s.data.scheduleIds.keys, ['p1|08:00']);
      expect(sched.calls, 2);
    });

    test('server logs are keyed by local date/time; taken/skipped win; pending/missed ignored; old logs of vanished plans stay', () async {
      final (s, sched, _) = await make();
      final local = DateTime(2026, 11, 3, 8);
      s.applyRemote(plans: [_plan('p1')], logs: const []);
      s.applyRemote(plans: [_plan('p1')], logs: [
        RemoteLog(planId: 'p1', scheduleId: 's1', status: 'taken', scheduledAt: local.toUtc(), takenAt: DateTime.utc(2026, 11, 3, 1, 10)),
        RemoteLog(planId: 'p1', scheduleId: 's1', status: 'skipped', scheduledAt: DateTime(2026, 11, 2, 8).toUtc()),
        RemoteLog(planId: 'p1', scheduleId: 's1', status: 'pending', scheduledAt: DateTime(2026, 11, 1, 8).toUtc()),
        RemoteLog(planId: 'p1', scheduleId: 's1', status: 'missed', scheduledAt: DateTime(2026, 10, 31, 8).toUtc()),
      ]);
      await s.flush();
      expect(s.data.logs['p1|2026-11-03|08:00']?.status, 'taken');
      // stored as a local timestamp (no 'Z'), like logs written by the app itself
      final takenAt = DateTime.parse(s.data.logs['p1|2026-11-03|08:00']!.at);
      expect(takenAt.isUtc, false);
      expect(takenAt, DateTime.utc(2026, 11, 3, 1, 10).toLocal());
      expect(takenAt.hour, DateTime.utc(2026, 11, 3, 1, 10).toLocal().hour);
      expect(s.data.logs['p1|2026-11-02|08:00']?.status, 'skipped');
      expect(DateTime.parse(s.data.logs['p1|2026-11-02|08:00']!.at), DateTime(2026, 11, 2, 8));
      expect(s.data.logs['p1|2026-11-02|08:00']!.at.endsWith('Z'), false);
      expect(s.data.logs.keys.where((k) => k.contains('2026-11-01') || k.contains('2026-10-31')), isEmpty);
      // overwrite a different local value, keep logs of a plan the server dropped
      s.applyRemote(plans: const [], logs: [
        RemoteLog(planId: 'p1', scheduleId: 's1', status: 'skipped', scheduledAt: local.toUtc()),
      ]);
      await s.flush();
      expect(s.data.meds, isEmpty);
      expect(s.data.logs['p1|2026-11-03|08:00']?.status, 'skipped');
      expect(s.data.logs['p1|2026-11-02|08:00']?.status, 'skipped');
      expect(sched.calls, greaterThan(0));
    });
  });
}

/// An outbox whose server is unreachable, so the queued ops stay visible to the test.
Future<LogOutbox> _offlineOutbox() async {
  final repo = FakeMedRepository()..onUpsert = (_) async => throw const AuthFailure(AuthFailureKind.network);
  return LogOutbox(await SharedPreferences.getInstance(), repo);
}

const _ids = {'m1|08:00': 'sch-m1', 'm2|08:00': 'sch-m2a', 'm2|18:00': 'sch-m2b'};

void outboxTests() {
  group('outbox', () {
    Future<(AppState, LogOutbox, Storage)> setUp({DateTime? at}) async {
      SharedPreferences.setMockInitialValues({});
      final outbox = await _offlineOutbox();
      final (s, _, storage) = await make(clock: () => at ?? DateTime(2026, 11, 4, 9), outbox: outbox);
      s.data = s.data.copyWith(scheduleIds: _ids);
      return (s, outbox, storage);
    }

    test('mark taken builds the op: ids, UTC scheduledAt, takenAt = now, late only after 60 minutes', () async {
      final (s, o, _) = await setUp(at: DateTime(2026, 11, 4, 9, 1));
      s.mark(itemsFor(s.data, date, s.now).first, DoseStatus.taken); // m1 08:00, 61 minutes
      final op = o.pending.single;
      expect(op.planId, 'm1');
      expect(op.scheduleId, 'sch-m1');
      expect(op.status, 'taken');
      expect(op.scheduledAt, DateTime(2026, 11, 4, 8));
      expect(op.toJson()['scheduledAt'], DateTime(2026, 11, 4, 8).toUtc().toIso8601String());
      expect(op.takenAt, DateTime(2026, 11, 4, 9, 1));
      expect(op.isLate, true);
    });

    test('exactly 60 minutes and 30 minutes are not late', () async {
      final (s, o, _) = await setUp(); // now 09:00, dose 08:00 = exactly 60
      s.mark(itemsFor(s.data, date, s.now).first, DoseStatus.taken);
      expect(o.pending.single.isLate, false);
      final (s2, o2, _) = await setUp(at: DateTime(2026, 11, 4, 8, 30));
      s2.mark(itemsFor(s2.data, date, s2.now).first, DoseStatus.taken);
      expect(o2.pending.single.isLate, false);
    });

    test('mark skipped is skipped and never late', () async {
      final (s, o, _) = await setUp(at: DateTime(2026, 11, 4, 12));
      s.mark(itemsFor(s.data, date, s.now).first, DoseStatus.skipped);
      expect(o.pending.single.status, 'skipped');
      expect(o.pending.single.isLate, false);
    });

    test('markMeal enqueues each logged dose only', () async {
      final (s, o, _) = await setUp();
      final all = itemsFor(s.data, date, s.now);
      final keys = s.markMeal(all.where((i) => i.time == '08:00' || i.time == '18:00').toList());
      expect(keys.length, 2); // the 18:00 dose is not due
      expect(o.pending.map((e) => e.scheduleId), ['sch-m1', 'sch-m2a']);
    });

    test('undo becomes a pending op with no takenAt, replacing the taken one', () async {
      final (s, o, _) = await setUp();
      final it = itemsFor(s.data, date, s.now).first;
      s.mark(it, DoseStatus.taken);
      s.undo(it);
      final op = o.pending.single;
      expect(op.status, 'pending');
      expect(op.takenAt, isNull);
      expect(op.isLate, false);
    });

    test('undoKeys enqueues pending for each key that had a log', () async {
      final (s, o, _) = await setUp();
      final keys = s.markMeal(itemsFor(s.data, date, s.now).where((i) => i.time == '08:00').toList());
      s.undoKeys(keys);
      expect(o.pending.map((e) => e.status), ['pending', 'pending']);
    });

    test('a dose without a scheduleId queues nothing and does not throw', () async {
      final (s, o, _) = await setUp();
      s.data = s.data.copyWith(scheduleIds: const {});
      final it = itemsFor(s.data, date, s.now).first;
      s.mark(it, DoseStatus.taken);
      s.markMeal([it]);
      s.undo(it);
      await s.applyNotificationAction('taken', it.key);
      expect(o.pendingCount, 0);
    });

    test('notification taken/skip enqueue, notyet does not', () async {
      final (s, o, _) = await setUp();
      await s.applyNotificationAction('notyet', 'm1|2026-11-04|08:00');
      expect(o.pendingCount, 0);
      await s.applyNotificationAction('taken', 'm1|2026-11-04|08:00');
      await s.applyNotificationAction('skip', 'm2|2026-11-04|08:00');
      expect(o.pending.map((e) => '${e.scheduleId}:${e.status}'), ['sch-m1:taken', 'sch-m2a:skipped']);
    });

    test('presses queued by the background isolate are enqueued with their press time', () async {
      final (s, o, storage) = await setUp();
      await storage.appendPending('taken\tm1|2026-11-04|08:00\t2026-11-04T08:20:00.000');
      await storage.appendPending('notyet\tm2|2026-11-04|08:00\t2026-11-04T08:21:00.000');
      await storage.appendPending('skip\tm2|2026-11-04|18:00\t2026-11-04T18:30:00.000');
      await s.reload();
      expect(o.pending.map((e) => '${e.scheduleId}:${e.status}'), ['sch-m1:taken', 'sch-m2b:skipped']);
      expect(o.pending.first.takenAt, DateTime(2026, 11, 4, 8, 20));
      expect(o.pending.first.isLate, false);
    });
  });
}
