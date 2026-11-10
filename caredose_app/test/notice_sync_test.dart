import 'dart:async';

import 'package:caredose/models/notice.dart';
import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/services/notice_repository.dart';
import 'package:caredose/services/notice_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_notice_repository.dart';

class FakeDisplay implements NoticeDisplay {
  final shown = <String>[];

  /// What show() reports; false = the plugin was not ready.
  bool ok = true;

  /// When set, show() waits for it (to keep a display in flight).
  Completer<void>? gate;
  @override
  Future<bool> show(int id, String title, String body) async {
    if (gate != null) await gate!.future;
    if (!ok) return false;
    shown.add(title);
    return true;
  }
}

Future<(FakeNoticeRepository, FakeDisplay, NoticeSync, SharedPreferences)> make({bool Function()? canPull}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo = FakeNoticeRepository();
  final display = FakeDisplay();
  return (repo, display, NoticeSync(repo, display, prefs, canPull: canPull), prefs);
}

void main() {
  test('pull shows unread notices oldest first, marks them read and remembers the ids', () async {
    final (repo, display, sync, prefs) = await make();
    repo.unread = [notice('1', title: 'a'), notice('2', title: 'b')];
    await sync.pull();
    expect(display.shown, ['a', 'b']);
    expect(repo.marked.expand((x) => x).toSet(), {'1', '2'});
    expect(prefs.getStringList('caredose_shown_notices'), ['1', '2']);
  });

  test('a notice arriving by Realtime and by pull at the same moment is shown once', () async {
    final (repo, display, sync, _) = await make();
    repo.unread = [notice('1', title: 'a')];
    sync.start();
    final pulling = sync.pull();
    repo.listener!(notice('1', title: 'a'));
    await pulling;
    await Future<void>.delayed(Duration.zero);
    expect(display.shown, ['a']);
    // and again later, from both sources
    repo.listener!(notice('1', title: 'a'));
    await sync.pull();
    expect(display.shown, ['a']);
  });

  test('a Realtime insert is shown and marked read', () async {
    final (repo, display, sync, _) = await make();
    sync.start();
    repo.listener!(notice('9', title: 'live'));
    await Future<void>.delayed(Duration.zero);
    expect(display.shown, ['live']);
    expect(repo.marked.expand((x) => x), ['9']);
  });

  test('shown but not marked read (offline): not shown again, markRead retried next pull', () async {
    final (repo, display, sync, _) = await make();
    repo.unread = [notice('1')];
    repo.markFailure = const AuthFailure(AuthFailureKind.network);
    await sync.pull(); // must not throw
    expect(display.shown, ['t']);
    repo.markFailure = null;
    await sync.pull();
    expect(display.shown, ['t']);
    expect(repo.marked.expand((x) => x), ['1']);
  });

  test('a message the plugin could not show stays unread and is shown by a later pull', () async {
    final (repo, display, sync, prefs) = await make();
    repo.unread = [notice('1', title: 'a')];
    display.ok = false; // plugin not initialised yet
    await sync.pull();
    expect(display.shown, isEmpty);
    expect(repo.marked, isEmpty);
    expect(prefs.getStringList('caredose_shown_notices') ?? <String>[], isEmpty);
    display.ok = true;
    await sync.pull();
    expect(display.shown, ['a']);
    expect(repo.marked.expand((x) => x), ['1']);
  });

  test('a duplicate that arrives while the first show is still failing is not marked read either', () async {
    final (repo, display, sync, _) = await make();
    repo.unread = [notice('1')];
    display.ok = false;
    display.gate = Completer<void>();
    sync.start();
    final pulling = sync.pull();
    await Future<void>.delayed(Duration.zero);
    repo.listener!(notice('1')); // same message over Realtime while show() is in flight
    await Future<void>.delayed(Duration.zero);
    display.gate!.complete();
    await pulling;
    await Future<void>.delayed(Duration.zero);
    expect(repo.marked, isEmpty);
  });

  test('does nothing while canPull is false', () async {
    final (repo, display, sync, _) = await make(canPull: () => false);
    repo.unread = [notice('1')];
    sync.start();
    await sync.pull();
    expect(repo.fetchCalls, 0);
    expect(repo.subscribes, 0);
    expect(display.shown, isEmpty);
  });

  test('stop cancels the subscription and drops a pull that was in flight', () async {
    final (repo, display, sync, _) = await make();
    repo.unread = [notice('1')];
    repo.gate = Completer<void>();
    sync.start();
    final pulling = sync.pull();
    sync.stop();
    repo.gate!.complete();
    await pulling;
    expect(display.shown, isEmpty);
    expect(repo.cancels, 1);
  });

  test('start twice subscribes once', () async {
    final (repo, _, sync, _) = await make();
    sync.start();
    sync.start();
    expect(repo.subscribes, 1);
  });

  test('the remembered ids are capped at 100, oldest dropped', () async {
    final (repo, _, sync, prefs) = await make();
    repo.unread = [for (var i = 0; i < 105; i++) notice('$i')];
    await sync.pull();
    final ids = prefs.getStringList('caredose_shown_notices')!;
    expect(ids.length, 100);
    expect(ids.first, '5');
    expect(ids.last, '104');
  });

  test('clearShown forgets everything so the next user starts clean', () async {
    final (repo, display, sync, prefs) = await make();
    repo.unread = [notice('1')];
    await sync.pull();
    await sync.clearShown();
    expect(prefs.getStringList('caredose_shown_notices'), isNull);
    await sync.pull();
    expect(display.shown.length, 2);
  });

  test('offline pull is quiet; an unexpected error is swallowed too', () async {
    final (repo, _, sync, _) = await make();
    repo.failure = const AuthFailure(AuthFailureKind.network);
    await sync.pull();
    repo.failure = null;
    repo.crash = StateError('boom');
    await sync.pull();
  });

  test('ids remembered by an earlier run are not shown again', () async {
    SharedPreferences.setMockInitialValues({
      'caredose_shown_notices': ['1']
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeNoticeRepository()..unread = [notice('1')];
    final display = FakeDisplay();
    await NoticeSync(repo, display, prefs).pull();
    expect(display.shown, isEmpty);
  });

  test('loadRecent returns the repository list, and [] when offline', () async {
    final (repo, _, sync, _) = await make();
    repo.recent = [notice('2'), notice('1')];
    expect((await sync.loadRecent()).map((n) => n.id), ['2', '1']);
    repo.failure = const AuthFailure(AuthFailureKind.network);
    expect(await sync.loadRecent(), isEmpty);
  });

  test('Notice.fromJson reads the row; a missing body is empty', () {
    final n = Notice.fromJson({'id': 'x', 'title': 'T', 'created_at': '2026-11-10T03:00:00+00:00', 'read': true});
    expect([n.id, n.title, n.body, n.read], ['x', 'T', '', true]);
    expect(n.createdAt.toUtc(), DateTime.utc(2026, 11, 10, 3));
  });
}
