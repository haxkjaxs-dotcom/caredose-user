import 'dart:async';

import 'package:caredose/models/remote_plan.dart';
import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/services/med_sync.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_med_repository.dart';
import 'helpers.dart';

const plan = RemotePlan(
  id: 'p1',
  name: 'ยาใหม่',
  dosage: '1 เม็ด',
  meal: 'หลังอาหาร',
  start: '2026-11-01',
  end: '',
  note: '',
  schedules: [PlanSchedule('s1', '08:00')],
);

void main() {
  test('pull applies plans and logs, asks for the last 30 days, then calls onPulled', () async {
    final s = await makeState();
    final repo = FakeMedRepository()..plans = [plan];
    var pulled = 0;
    final sync = MedSync(repo, s, onPulled: () async => pulled++);
    await sync.pull();
    await s.flush();
    expect(s.data.meds.map((m) => m.id), ['p1']);
    expect(s.data.scheduleIds['p1|08:00'], 's1');
    expect(repo.lastSince, testNow.subtract(const Duration(days: 30)));
    expect(lastScheduler.calls, 1);
    expect(pulled, 1);
  });

  test('network failure leaves data untouched and does not throw', () async {
    final s = await makeState();
    final before = s.data.meds.map((m) => m.id).toList();
    final repo = FakeMedRepository()..failure = const AuthFailure(AuthFailureKind.network);
    var pulled = 0;
    await MedSync(repo, s, onPulled: () async => pulled++).pull();
    await s.flush();
    expect(s.data.meds.map((m) => m.id), before);
    expect(lastScheduler.calls, 0);
    expect(pulled, 0);
  });

  test('a second pull while one is running is skipped', () async {
    final s = await makeState();
    final repo = FakeMedRepository()
      ..plans = [plan]
      ..gate = Completer<void>();
    final sync = MedSync(repo, s);
    final first = sync.pull();
    await sync.pull();
    expect(repo.plansCalls, 1);
    repo.gate!.complete();
    await first;
    await sync.pull(); // free again
    expect(repo.plansCalls, 2);
  });

  test('stop() while a pull is in flight discards its result; a new pull works after', () async {
    final s = await makeState();
    final repo = FakeMedRepository()
      ..plans = [plan]
      ..gate = Completer<void>();
    var pulled = 0;
    final sync = MedSync(repo, s, onPulled: () async => pulled++);
    final stale = sync.pull();
    sync.stop();
    repo.gate!.complete();
    await stale;
    await s.flush();
    expect(s.data.meds.map((m) => m.id), ['m1', 'm2', 'm3']);
    expect(lastScheduler.calls, 0);
    expect(pulled, 0);
    repo.gate = null;
    await sync.pull(); // not blocked by the stale pull's single-flight flag
    expect(s.data.meds.map((m) => m.id), ['p1']);
    expect(pulled, 1);
  });

  test('canPull false: pull does nothing; flipping false mid-flight discards the result', () async {
    final s = await makeState();
    final repo = FakeMedRepository()..plans = [plan];
    var ok = false;
    final sync = MedSync(repo, s, canPull: () => ok);
    await sync.pull();
    expect(repo.plansCalls, 0);
    ok = true;
    repo.gate = Completer<void>();
    final f = sync.pull();
    ok = false;
    repo.gate!.complete();
    await f;
    expect(s.data.meds.map((m) => m.id), ['m1', 'm2', 'm3']);
  });

  test('beforePull runs before fetching, errors are swallowed, skipped when canPull is false', () async {
    final s = await makeState();
    final repo = FakeMedRepository()..plans = [plan];
    final sync = MedSync(repo, s, beforePull: () async {
      repo.order.add('beforePull');
      throw StateError('flush failed');
    });
    await sync.pull();
    expect(repo.order, ['beforePull', 'fetchPlans']);
    expect(s.data.meds.map((m) => m.id), ['p1']);

    final repo2 = FakeMedRepository();
    await MedSync(repo2, s, canPull: () => false, beforePull: () async => repo2.order.add('beforePull')).pull();
    expect(repo2.order, isEmpty);
  });

  test('an unexpected error does not escape, leaves data alone and does not block the next pull', () async {
    final s = await makeState();
    final repo = FakeMedRepository()
      ..plans = [plan]
      ..crash = StateError('boom');
    final sync = MedSync(repo, s);
    await sync.pull();
    expect(s.data.meds.map((m) => m.id), ['m1', 'm2', 'm3']);
    repo.crash = null;
    await sync.pull();
    expect(s.data.meds.map((m) => m.id), ['p1']);
  });

  testWidgets('start pulls every 5 minutes until stop; both are idempotent', (tester) async {
    final s = await makeState();
    final repo = FakeMedRepository();
    final sync = MedSync(repo, s);
    sync.start();
    sync.start();
    await tester.pump(const Duration(minutes: 5));
    expect(repo.plansCalls, 1);
    await tester.pump(const Duration(minutes: 5));
    expect(repo.plansCalls, 2);
    sync.stop();
    sync.stop();
    await tester.pump(const Duration(minutes: 20));
    expect(repo.plansCalls, 2);
  });
}
