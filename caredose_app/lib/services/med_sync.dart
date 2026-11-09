import 'dart:async';

import 'package:flutter/foundation.dart';

import '../state/app_state.dart';
import 'auth_repository.dart';
import 'med_repository.dart';

/// Pulls the patient's medication plans and dose logs from the server into [AppState].
class MedSync {
  MedSync(
    this._repo,
    this._state, {
    this.onPulled,
    this.beforePull,
    bool Function()? canPull,
  }) : _canPull = canPull ?? (() => true);

  final MedRepository _repo;
  final AppState _state;

  /// Runs after each successful pull (the outbox flush hooks in here).
  final Future<void> Function()? onPulled;

  /// Awaited at the start of each pull, before fetching (the outbox flush hooks in here). Errors are ignored.
  final Future<void> Function()? beforePull;

  /// False while signed out: nothing is fetched or applied.
  final bool Function() _canPull;
  Timer? _timer;
  bool _running = false;
  int _epoch = 0; // bumped by stop(); a pull from an older epoch is stale and must not touch the data

  Future<void> pull() async {
    if (_running || !_canPull()) return;
    _running = true;
    final epoch = _epoch;
    try {
      try {
        await beforePull?.call();
      } catch (e) {
        debugPrint('beforePull failed: $e');
      }
      if (epoch != _epoch) return;
      final plans = await _repo.fetchPlans();
      final logs = await _repo.fetchLogs(
        _state.clockNow.subtract(const Duration(days: 30)),
      );
      if (epoch != _epoch || !_canPull()) return;
      _state.applyRemote(plans: plans, logs: logs);
      await onPulled?.call();
    } on AuthFailure {
      // Offline or signed out: keep what we have.
    } catch (e) {
      debugPrint('pull failed: $e');
    } finally {
      // a stale pull must not release a newer pull's flag
      if (epoch == _epoch) _running = false;
    }
  }

  void start() =>
      _timer ??= Timer.periodic(const Duration(minutes: 5), (_) => pull());

  void stop() {
    _timer?.cancel();
    _timer = null;
    _epoch++;
    _running = false;
  }
}
