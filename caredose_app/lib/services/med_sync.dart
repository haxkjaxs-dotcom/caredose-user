import 'dart:async';

import '../state/app_state.dart';
import 'auth_repository.dart';
import 'med_repository.dart';

/// Pulls the patient's medication plans and dose logs from the server into [AppState].
class MedSync {
  MedSync(this._repo, this._state, {this.onPulled});

  final MedRepository _repo;
  final AppState _state;

  /// Runs after each successful pull (the outbox flush hooks in here).
  final Future<void> Function()? onPulled;
  Timer? _timer;
  bool _running = false;

  Future<void> pull() async {
    if (_running) return;
    _running = true;
    try {
      final plans = await _repo.fetchPlans();
      final logs = await _repo.fetchLogs(_state.clockNow.subtract(const Duration(days: 30)));
      _state.applyRemote(plans: plans, logs: logs);
      await onPulled?.call();
    } on AuthFailure {
      // Offline or signed out: keep what we have.
    } finally {
      _running = false;
    }
  }

  void start() => _timer ??= Timer.periodic(const Duration(minutes: 5), (_) => pull());

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
