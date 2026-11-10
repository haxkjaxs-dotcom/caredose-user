import 'dart:async';
import 'dart:convert';

import 'package:caredose/models/remote_plan.dart';
import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/services/log_outbox.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_med_repository.dart';

LogOp op(String sid, int hour, {String status = 'taken'}) => LogOp(
      planId: 'p1',
      scheduleId: sid,
      status: status,
      scheduledAt: DateTime.utc(2026, 11, 4, hour),
      takenAt: status == 'pending' ? null : DateTime.utc(2026, 11, 4, hour, 5),
    );

Future<(LogOutbox, FakeMedRepository, SharedPreferences)> make([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final repo = FakeMedRepository();
  return (LogOutbox(p, repo), repo, p);
}

void main() {
  test('add keeps order, persists, and a new instance on the same prefs sees it', () async {
    final (o, repo, prefs) = await make();
    await o.add(op('s1', 1));
    await o.add(op('s2', 2));
    expect(o.pending.map((e) => e.scheduleId), ['s1', 's2']);
    expect(o.pendingCount, 2);
    final o2 = LogOutbox(prefs, repo);
    expect(o2.pending.map((e) => e.scheduleId), ['s1', 's2']);
    expect(o2.pending.first.scheduledAt, DateTime.utc(2026, 11, 4, 1));
  });

  test('same schedule and instant is replaced by the latest op', () async {
    final (o, _, _) = await make();
    await o.add(op('s1', 1));
    await o.add(op('s2', 2));
    await o.add(op('s1', 1, status: 'pending'));
    expect(o.pending.map((e) => '${e.scheduleId}:${e.status}'), ['s2:taken', 's1:pending']);
    await o.add(op('s1', 5)); // other instant: kept separately
    expect(o.pendingCount, 3);
  });

  test('flush sends in order and empties the queue (also on disk)', () async {
    final (o, repo, prefs) = await make();
    await o.add(op('s1', 1));
    await o.add(op('s2', 2));
    await o.flush();
    expect(repo.upserts.map((e) => e.scheduleId), ['s1', 's2']);
    expect(o.pendingCount, 0);
    expect(LogOutbox(prefs, repo).pendingCount, 0);
  });

  test('Review Focus: network failure mid-queue, then a restart, sends each entry exactly once', () async {
    final (o, repo, prefs) = await make();
    for (var i = 1; i <= 4; i++) {
      await o.add(op('s$i', i));
    }
    repo.onUpsert = (e) async {
      if (e.scheduleId == 's3') throw const AuthFailure(AuthFailureKind.network);
    };
    await o.flush();
    expect(repo.upserts.map((e) => e.scheduleId), ['s1', 's2']);
    expect(o.pending.map((e) => e.scheduleId), ['s3', 's4']);

    // app killed and relaunched: a fresh outbox on the same prefs
    repo.onUpsert = null;
    final o2 = LogOutbox(prefs, repo);
    expect(o2.pending.map((e) => e.scheduleId), ['s3', 's4']);
    await o2.flush();
    expect(repo.upserts.map((e) => e.scheduleId), ['s1', 's2', 's3', 's4']);
    expect(repo.upserts.length, 4);
    expect(LogOutbox(prefs, repo).pendingCount, 0);
  });

  test('rejected entry is dropped and the next one is still sent', () async {
    final (o, repo, _) = await make();
    await o.add(op('s1', 1));
    await o.add(op('s2', 2));
    repo.onUpsert = (e) async {
      if (e.scheduleId == 's1') throw const AuthFailure(AuthFailureKind.rejected);
    };
    await o.flush();
    expect(repo.upserts.map((e) => e.scheduleId), ['s2']);
    expect(o.pendingCount, 0);
  });

  for (final kind in [AuthFailureKind.unknown, AuthFailureKind.rateLimited, AuthFailureKind.network]) {
    test('$kind stops the flush and keeps every unsent entry', () async {
      final (o, repo, _) = await make();
      await o.add(op('s1', 1));
      await o.add(op('s2', 2));
      repo.onUpsert = (e) async => throw AuthFailure(kind);
      await o.flush();
      expect(repo.upsertCalls, 1);
      expect(o.pending.map((e) => e.scheduleId), ['s1', 's2']);
    });
  }

  test('a non-AuthFailure error is contained and stops the flush', () async {
    final (o, repo, _) = await make();
    await o.add(op('s1', 1));
    await o.add(op('s2', 2));
    repo.onUpsert = (e) async => throw StateError('boom');
    await o.flush(); // must not throw
    expect(repo.upsertCalls, 1);
    expect(o.pendingCount, 2);
  });

  test('concurrent flushes do not send the same entry twice', () async {
    final (o, repo, _) = await make();
    await o.add(op('s1', 1));
    final gate = Completer<void>();
    repo.onUpsert = (e) => gate.future;
    final a = o.flush();
    final b = o.flush();
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await Future.wait([a, b]);
    expect(repo.upsertCalls, 1);
    expect(o.pendingCount, 0);
  });

  test('an op added during an in-flight send is sent too, and a replaced in-flight op is not lost', () async {
    final (o, repo, _) = await make();
    await o.add(op('s1', 1));
    final gate = Completer<void>();
    repo.onUpsert = (e) async {
      if (repo.upsertCalls == 1) await gate.future;
    };
    final f = o.flush();
    await Future<void>.delayed(Duration.zero);
    await o.add(op('s1', 1, status: 'pending')); // replaces the op being sent
    gate.complete();
    await f;
    expect(repo.upserts.map((e) => e.status), ['taken', 'pending']);
    expect(o.pendingCount, 0);
  });

  test('clear during an in-flight flush leaves the queue empty on disk too', () async {
    final (o, repo, prefs) = await make();
    await o.add(op('s1', 1));
    await o.add(op('s2', 2));
    final gate = Completer<void>();
    repo.onUpsert = (e) => gate.future;
    final f = o.flush();
    await Future<void>.delayed(Duration.zero);
    await o.clear();
    gate.complete();
    await f;
    expect(repo.upsertCalls, 1); // the stale flush does not go on to s2
    expect(o.pendingCount, 0);
    expect(LogOutbox(prefs, repo).pendingCount, 0);
  });

  test('a flush started after clear is not blocked by the stale one', () async {
    final (o, repo, _) = await make();
    await o.add(op('s1', 1));
    final gate = Completer<void>();
    repo.onUpsert = (e) => gate.future;
    final stale = o.flush();
    await Future<void>.delayed(Duration.zero);
    await o.clear();
    await o.add(op('s9', 9));
    final fresh = o.flush();
    gate.complete();
    await Future.wait([stale, fresh]);
    expect(repo.upserts.map((e) => e.scheduleId), contains('s9'));
    expect(o.pendingCount, 0);
  });

  test('a corrupt stored value is ignored', () async {
    for (final bad in ['not json', '{"a":1}', '42']) {
      final (o, _, _) = await make({'caredose_outbox': bad});
      expect(o.pendingCount, 0, reason: bad);
    }
  });

  test('entries with an empty planId or scheduleId are dropped at load', () async {
    final (o, _, _) = await make({
      'caredose_outbox': jsonEncode([
        {...op('s1', 1).toJson(), 'scheduleId': ''},
        {...op('s2', 2).toJson(), 'planId': ''},
        {...op('s3', 3).toJson()}..remove('scheduleId'),
        op('s4', 4).toJson(),
      ]),
    });
    expect(o.pending.map((e) => e.scheduleId), ['s4']);
  });

  test('a rejected head entry is logged when dropped and never blocks the ones behind it', () async {
    final (o, repo, _) = await make();
    await o.add(op('bad', 1));
    await o.add(op('s2', 2));
    await o.add(op('s3', 3));
    repo.onUpsert = (e) async {
      if (e.scheduleId == 'bad') throw const AuthFailure(AuthFailureKind.rejected);
    };
    final lines = <String>[];
    final old = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
    try {
      await o.flush();
    } finally {
      debugPrint = old;
    }
    expect(repo.upserts.map((e) => e.scheduleId), ['s2', 's3']);
    expect(o.pendingCount, 0);
    expect(lines.where((l) => l.contains('bad') && l.contains('rejected')), hasLength(1));
  });

  test('one bad entry among good ones is dropped', () async {
    final (o, _, _) = await make({
      'caredose_outbox': jsonEncode([op('s1', 1).toJson(), {'scheduledAt': 'nope'}, 7, op('s2', 2).toJson()]),
    });
    expect(o.pending.map((e) => e.scheduleId), ['s1', 's2']);
  });
}
