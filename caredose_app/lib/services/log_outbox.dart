import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../models/remote_plan.dart';
import 'auth_repository.dart';
import 'med_repository.dart';

/// Dose records waiting to reach the server. Kept in SharedPreferences so a killed app still sends
/// them on the next launch; sending is an idempotent upsert, so a crash between "sent" and "removed"
/// can at worst send one entry twice.
class LogOutbox {
  LogOutbox(this._prefs, this._repo) : _queue = _load(_prefs);

  static const _key = 'caredose_outbox';

  final SharedPreferences _prefs;
  final MedRepository _repo;
  final List<LogOp> _queue;
  int _epoch = 0; // bumped by clear(): a flush from an older epoch must not touch the queue again
  Future<void>? _inflight;
  int _inflightEpoch = 0;

  List<LogOp> get pending => List.unmodifiable(_queue);
  int get pendingCount => _queue.length;

  /// A corrupt list or entry is dropped, never thrown: losing one record beats a crash at launch.
  static List<LogOp> _load(SharedPreferences prefs) {
    final out = <LogOp>[];
    try {
      final raw = prefs.getString(_key);
      if (raw == null) return out;
      final list = jsonDecode(raw);
      if (list is! List) return out;
      for (final e in list) {
        try {
          final op = LogOp.fromJson(Json.from(e as Map));
          if (op.planId.isNotEmpty && op.scheduleId.isNotEmpty) out.add(op); // the server could never accept it
        } catch (_) {}
      }
    } catch (_) {}
    return out;
  }

  Future<void> _save() => _prefs.setString(_key, jsonEncode([for (final o in _queue) o.toJson()]));

  /// Queues [op], replacing an earlier one for the same dose (the latest press wins). The queue
  /// changes synchronously; the returned future completes once it is on disk.
  Future<void> add(LogOp op) {
    _queue.removeWhere((o) => o.scheduleId == op.scheduleId && o.scheduledAt.isAtSameMomentAs(op.scheduledAt));
    _queue.add(op);
    return _save();
  }

  Future<void> clear() {
    _epoch++;
    _queue.clear();
    return _save();
  }

  /// Sends the queue one entry at a time. A second call while one is running shares it.
  Future<void> flush() {
    if (_inflight != null && _inflightEpoch == _epoch) return _inflight!;
    final epoch = _inflightEpoch = _epoch;
    late final Future<void> f;
    f = _run(epoch).whenComplete(() {
      if (identical(_inflight, f)) _inflight = null;
    });
    return _inflight = f;
  }

  Future<void> _run(int epoch) async {
    while (epoch == _epoch && _queue.isNotEmpty) {
      final op = _queue.first;
      var drop = true;
      try {
        await _repo.upsertLog(op);
      } on AuthFailure catch (f) {
        drop = f.kind == AuthFailureKind.rejected; // the server will never take it
        if (!drop) return;
        debugPrint('outbox dropped ${op.status} for schedule ${op.scheduleId} at ${op.scheduledAt.toUtc().toIso8601String()}: rejected');
      } catch (e) {
        debugPrint('outbox flush failed: $e');
        return;
      }
      if (epoch != _epoch) return; // cleared meanwhile: write nothing back
      // By identity: a newer press for the same dose may have replaced `op` while it was in flight.
      if (_queue.remove(op)) await _save();
    }
  }
}
