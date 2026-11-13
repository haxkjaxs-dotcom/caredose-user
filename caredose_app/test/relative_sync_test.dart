import 'dart:async';

import 'package:caredose/models/models.dart';
import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/services/relative_sync.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_relative_repository.dart';
import 'helpers.dart';

const net = AuthFailure(AuthFailureKind.network);

void main() {
  test('pull replaces the local copy with the server list, admin-made ones included', () async {
    final s = await makeState();
    final repo = FakeRelativeRepository()
      ..server = [
        const Relative(id: 'u1', name: 'ก', rel: 'ลูก', phone: '081'),
        const Relative(id: 'u2', name: 'ข', rel: 'พี่', phone: '082', editable: false),
      ];
    await RelativeSync(repo, s).pull();
    expect(s.data.relatives.map((r) => r.id), ['u1', 'u2']);
    expect(s.data.relatives.last.editable, false);
  });

  test('a failed pull keeps the local copy and does not throw', () async {
    final s = await makeState();
    s.applyRelatives(const [Relative(id: 'u1', name: 'ก', phone: '081')]);
    final repo = FakeRelativeRepository()..failure = net;
    await RelativeSync(repo, s).pull();
    expect(s.data.relatives.map((r) => r.id), ['u1']);
  });

  test('pull does nothing while signed out, and a second pull during one is skipped', () async {
    final s = await makeState();
    final repo = FakeRelativeRepository();
    await RelativeSync(repo, s, canPull: () => false).pull();
    expect(repo.fetchCalls, 0);

    repo.gate = Completer<void>();
    final sync = RelativeSync(repo, s);
    final first = sync.pull();
    await sync.pull();
    expect(repo.fetchCalls, 1);
    repo.gate!.complete();
    await first;
  });

  test('a pull that finishes after the user signed out is dropped', () async {
    final s = await makeState();
    s.applyRelatives(const []);
    var ready = true;
    final repo = FakeRelativeRepository()
      ..server = [const Relative(id: 'u1', name: 'ก', phone: '081')]
      ..gate = Completer<void>();
    final pull = RelativeSync(repo, s, canPull: () => ready).pull();
    ready = false;
    repo.gate!.complete();
    await pull;
    expect(s.data.relatives, isEmpty);
  });

  test('save sends the form to the server and keeps the id it returns', () async {
    final s = await makeState();
    s.applyRelatives(const []);
    final repo = FakeRelativeRepository();
    await RelativeSync(repo, s).save(name: 'ก', rel: 'ลูก', phone: '081');
    expect(repo.saved.single, (id: null, name: 'ก', rel: 'ลูก', phone: '081'));
    expect(s.data.relatives.single.id, 'u1');
    expect(s.data.relatives.single.editable, true);
  });

  test('saving an existing relative updates it in place', () async {
    final s = await makeState();
    s.applyRelatives(const [Relative(id: 'u1', name: 'ก', rel: 'ลูก', phone: '081')]);
    final repo = FakeRelativeRepository()..server = [const Relative(id: 'u1', name: 'ก', rel: 'ลูก', phone: '081')];
    await RelativeSync(repo, s).save(id: 'u1', name: 'ข', rel: 'แม่', phone: '082');
    expect(repo.saved.single.id, 'u1');
    expect(s.data.relatives.map((r) => (r.id, r.name, r.rel)), [('u1', 'ข', 'แม่')]);
  });

  test('a failed save throws and leaves the copy as it was', () async {
    final s = await makeState();
    s.applyRelatives(const [Relative(id: 'u1', name: 'ก', phone: '081')]);
    final repo = FakeRelativeRepository()..failure = net;
    await expectLater(RelativeSync(repo, s).save(name: 'x', rel: '', phone: '1'), throwsA(isA<AuthFailure>()));
    expect(s.data.relatives.map((r) => r.id), ['u1']);
  });

  test('delete removes it from the server and the copy; a failed delete throws and keeps it', () async {
    final s = await makeState();
    s.applyRelatives(const [Relative(id: 'u1', name: 'ก', phone: '081')]);
    final repo = FakeRelativeRepository()..server = [const Relative(id: 'u1', name: 'ก', phone: '081')];
    final sync = RelativeSync(repo, s);
    repo.failure = net;
    await expectLater(sync.delete('u1'), throwsA(isA<AuthFailure>()));
    expect(s.data.relatives.map((r) => r.id), ['u1']);
    repo.failure = null;
    await sync.delete('u1');
    expect(repo.deleted, ['u1']);
    expect(s.data.relatives, isEmpty);
  });

  test('a pull that was in flight while the user saved does not wipe the saved relative', () async {
    final s = await makeState();
    s.applyRelatives(const []);
    final gate = Completer<void>();
    final repo = FakeRelativeRepository()..gate = gate;
    final sync = RelativeSync(repo, s);
    final pull = sync.pull(); // the server list it will return was read before the save: empty
    await Future<void>.delayed(Duration.zero);
    await sync.save(name: 'ก', rel: 'ลูก', phone: '081');
    gate.complete();
    await pull;
    expect(s.data.relatives.map((r) => r.id), ['u1']);
  });
}
