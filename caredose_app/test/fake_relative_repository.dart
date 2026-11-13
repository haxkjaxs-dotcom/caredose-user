import 'dart:async';

import 'package:caredose/models/models.dart';
import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/services/relative_repository.dart';

class FakeRelativeRepository implements RelativeRepository {
  List<Relative> server = [];
  AuthFailure? failure;

  /// When set, fetch waits for it (to hold a pull open). The list it returns is the one from before the wait.
  Completer<void>? gate;
  /// When set, save waits for it (to finish a save after something else happened).
  Completer<void>? saveGate;
  int fetchCalls = 0, saveCalls = 0, deleteCalls = 0;
  final saved = <({String? id, String name, String rel, String phone})>[];
  final deleted = <String>[];
  int _n = 0;

  @override
  Future<List<Relative>> fetch() async {
    fetchCalls++;
    final snapshot = List.of(server);
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return snapshot;
  }

  @override
  Future<String> save({String? id, required String name, required String rel, required String phone}) async {
    saveCalls++;
    if (failure != null) throw failure!;
    if (saveGate != null) await saveGate!.future;
    saved.add((id: id, name: name, rel: rel, phone: phone));
    final rid = id ?? 'u${++_n}';
    final r = Relative(id: rid, name: name, rel: rel, phone: phone);
    server = [for (final x in server) if (x.id != rid) x, r];
    return rid;
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls++;
    if (failure != null) throw failure!;
    deleted.add(id);
    server = server.where((x) => x.id != id).toList();
  }
}
