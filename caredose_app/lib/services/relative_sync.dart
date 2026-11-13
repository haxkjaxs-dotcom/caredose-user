import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import 'auth_repository.dart';
import 'relative_repository.dart';

/// Keeps the patient's relatives on the server and a copy in [AppState]. The server is the truth:
/// a pull replaces the copy; add, change and delete need the network and touch the copy only after the server accepted them.
class RelativeSync {
  RelativeSync(this._repo, this._state, {bool Function()? canPull}) : _canPull = canPull ?? (() => true);

  final RelativeRepository _repo;
  final AppState _state;

  /// False while signed out: nothing is fetched or applied.
  final bool Function() _canPull;
  bool _running = false;

  /// Bumped by every accepted save/delete; a pull that started before it holds an older list and is dropped.
  int _version = 0;

  /// Bumped by [reset]; anything that started before it belongs to the previous user and is dropped.
  int _epoch = 0;

  /// Never throws: offline or signed out keeps the copy.
  Future<void> pull() async {
    if (_running || !_canPull()) return;
    _running = true;
    final version = _version;
    final epoch = _epoch;
    try {
      final list = await _repo.fetch();
      if (epoch != _epoch || version != _version || !_canPull()) return;
      _state.applyRelatives(list);
    } on AuthFailure {
      // offline: keep what we have
    } catch (e) {
      debugPrint('relatives pull failed: $e');
    } finally {
      // a pull from before a reset must not release the flag of the next user's pull
      if (epoch == _epoch) _running = false;
    }
  }

  /// Sign-out: requests still in flight belong to the previous user and must not touch the next user's copy.
  void reset() {
    _epoch++;
    _running = false;
  }

  /// Throws [AuthFailure] when the server refuses or is unreachable; the copy is then unchanged.
  Future<void> save({String? id, required String name, required String rel, required String phone}) async {
    final epoch = _epoch;
    final rid = await _repo.save(id: id, name: name, rel: rel, phone: phone);
    if (epoch != _epoch) return; // signed out meanwhile: the server has it, the next user's copy must not
    _version++;
    _state.saveRelative(Relative(id: rid, name: name, rel: rel, phone: phone));
  }

  /// Throws [AuthFailure] like [save].
  Future<void> delete(String id) async {
    final epoch = _epoch;
    await _repo.delete(id);
    if (epoch != _epoch) return;
    _version++;
    _state.deleteRelative(id);
  }
}
