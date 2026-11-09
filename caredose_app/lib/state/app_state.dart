import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../logic/bmi.dart';
import '../logic/dose_items.dart';
import '../logic/thai_date.dart';
import '../models/models.dart';
import '../models/remote_plan.dart';
import '../services/log_outbox.dart';
import '../services/notification_actions.dart';
import '../services/storage.dart';

abstract class NotificationScheduler {
  Future<void> reschedule(AppData d, Set<String> dismissed, DateTime now);
}

/// System notification permission, so the settings screen can be tested without the plugin.
abstract class NotificationPermissions {
  Future<bool> permissionsGranted();
  Future<bool> requestPermissions();
}

class AppState extends ChangeNotifier {
  AppState(this._storage, this._scheduler, {DateTime Function()? clock, this._outbox})
      : _clock = clock ?? DateTime.now {
    now = _clock();
    data = _storage.load(now);
    dismissed = _storage.loadDismissed();
  }

  final Storage _storage;
  final NotificationScheduler _scheduler;
  final DateTime Function() _clock;
  final LogOutbox? _outbox;
  late AppData data;
  late Set<String> dismissed;
  late DateTime now;
  Future<void> _last = Future.value();

  /// False while signed out: nothing is scheduled, so the sample medicines never ring.
  bool remindersEnabled = true;

  DateTime get clockNow => _clock();

  /// Completes when all pending saves and reschedules have finished.
  Future<void> flush() => _last;

  void _commit(AppData d) {
    data = d;
    notifyListeners();
    _persist();
  }

  void _persist() {
    _last = _last.then((_) async {
      // Apply background button presses first so this save cannot overwrite them.
      if (await _drainPending()) notifyListeners();
      await _storage.save(data);
      await _storage.saveDismissed(dismissed);
      await _scheduler.reschedule(remindersEnabled ? data : data.copyWith(notify: false), dismissed, _clock());
    }).catchError((Object e) {
      debugPrint('persist/reschedule failed: $e');
    });
  }

  /// Applies button presses queued by the background isolate. Returns true if any.
  Future<bool> _drainPending() async {
    await _storage.refresh();
    final entries = _storage.loadPending();
    if (entries.isEmpty) return false;
    for (final e in entries) {
      final p = e.split('\t');
      if (p.length != 3) continue;
      final r = applyDoseAction(data, dismissed, p[0], p[1], DateTime.tryParse(p[2]) ?? _clock());
      data = r.data;
      dismissed = r.dismissed;
      _enqueue([p[1]], _statusOf(p[0]), DateTime.tryParse(p[2]) ?? _clock());
    }
    await _storage.removePending(entries.length);
    return true;
  }

  void setRemindersEnabled(bool v) {
    if (v == remindersEnabled) return;
    remindersEnabled = v;
    _persist();
  }

  /// Re-plans notifications now (respecting [remindersEnabled]).
  Future<void> rescheduleNow() {
    _persist();
    return flush();
  }

  void tick() {
    now = _clock();
    notifyListeners();
  }

  /// Picks up notification-button presses made while the UI was not running
  /// or not showing. Saves and reschedules only if there were any.
  Future<void> reload() async {
    await flush();
    now = _clock();
    if (await _drainPending()) {
      notifyListeners();
      _persist();
      await flush();
    } else {
      notifyListeners();
    }
  }

  /// Handles a notification button pressed while the app process is alive.
  Future<void> applyNotificationAction(String actionId, String key) async {
    final r = applyDoseAction(data, dismissed, actionId, key, _clock());
    dismissed = r.dismissed;
    _commit(r.data);
    _enqueue([key], _statusOf(actionId), _clock());
    await flush();
  }

  /// `taken` | `skipped` for a notification button, null for anything that records no dose (`notyet`).
  String? _statusOf(String actionId) => switch (actionId) { 'taken' => 'taken', 'skip' => 'skipped', _ => null };

  /// Queues one server record per dose key and starts sending. A dose whose schedule the server has not
  /// told us about yet is skipped silently. [status] null = nothing to send.
  void _enqueue(Iterable<String> keys, String? status, DateTime at) {
    final outbox = _outbox;
    if (outbox == null || status == null) return;
    var any = false;
    for (final key in keys) {
      final p = key.split('|');
      final scheduleId = p.length == 3 ? data.scheduleIds['${p[0]}|${p[2]}'] : null;
      if (scheduleId == null) continue;
      final scheduledAt = doseTime(p[1], p[2]);
      final taken = status == 'taken';
      outbox.add(LogOp(
        planId: p[0],
        scheduleId: scheduleId,
        status: status,
        scheduledAt: scheduledAt,
        takenAt: status == 'pending' ? null : at,
        isLate: taken && at.difference(scheduledAt) > const Duration(minutes: 60),
      ));
      any = true;
    }
    if (any) unawaited(outbox.flush()); // errors are contained inside flush
  }

  void _setLog(String key, DoseStatus s) {
    final status = s == DoseStatus.skipped ? 'skipped' : 'taken';
    final at = _clock();
    _commit(data.copyWith(logs: {...data.logs, key: DoseLog(status, at.toIso8601String())}));
    _enqueue([key], status, at);
  }

  void mark(DoseItem it, DoseStatus s) => _setLog(it.key, s);

  void undo(DoseItem it) => undoKeys([it.key]);

  /// Logs `taken` for items that are due and unrecorded; returns the keys logged.
  List<String> markMeal(List<DoseItem> items) {
    final due = items.where((it) {
      if (data.logs.containsKey(it.key)) return false;
      final day = it.key.split('|')[1];
      return !doseTime(day, it.time).isAfter(now);
    }).toList();
    if (due.isEmpty) return const [];
    final at = _clock().toIso8601String();
    final logs = {...data.logs, for (final it in due) it.key: DoseLog('taken', at)};
    _commit(data.copyWith(logs: logs));
    final keys = due.map((e) => e.key).toList();
    _enqueue(keys, 'taken', _clock());
    return keys;
  }

  void undoKeys(List<String> keys) {
    final had = keys.where(data.logs.containsKey).toList();
    final logs = {...data.logs}..removeWhere((k, _) => keys.contains(k));
    _commit(data.copyWith(logs: logs));
    _enqueue(had, 'pending', _clock());
  }

  /// Replaces the medicines with the server's plans and merges its taken/skipped logs.
  /// Does nothing (no save, no reschedule, no notify) when nothing actually changed.
  void applyRemote({required List<RemotePlan> plans, required List<RemoteLog> logs}) {
    final scheduleIds = {
      for (final p in plans) for (final s in p.schedules) '${p.id}|${s.time}': s.id,
    };
    final merged = {...data.logs};
    for (final l in logs) {
      if (l.status != 'taken' && l.status != 'skipped') continue; // pending/missed carry no information
      final t = l.scheduledAt.toLocal();
      final hh = t.hour.toString().padLeft(2, '0'), mm = t.minute.toString().padLeft(2, '0');
      merged['${l.planId}|${dateKey(t)}|$hh:$mm'] = DoseLog(l.status, (l.takenAt ?? l.scheduledAt).toLocal().toIso8601String());
    }
    final next = data.copyWith(meds: [for (final p in plans) p.toMed()], scheduleIds: scheduleIds, logs: merged);
    String sig(AppData d) => jsonEncode([d.meds.map((m) => m.toJson()).toList(), d.scheduleIds, d.logs.map((k, v) => MapEntry(k, v.toJson()))]);
    if (sig(next) == sig(data)) return;
    _commit(next);
  }

  void saveMed(Med m) {
    final exists = data.meds.any((x) => x.id == m.id);
    _commit(data.copyWith(meds: exists ? [for (final x in data.meds) x.id == m.id ? m : x] : [...data.meds, m]));
  }

  void saveRelative(Relative r) {
    final exists = data.relatives.any((x) => x.id == r.id);
    _commit(data.copyWith(relatives: exists ? [for (final x in data.relatives) x.id == r.id ? r : x] : [...data.relatives, r]));
  }

  void deleteRelative(String id) => _commit(data.copyWith(relatives: data.relatives.where((r) => r.id != id).toList()));

  void addBmi(double w, double h) {
    final v = bmiValue(w, h);
    final rec = BmiRecord(
      id: now.microsecondsSinceEpoch.toRadixString(36),
      w: w,
      h: h,
      v: v,
      cat: bmiCategory(v),
      at: _clock().toIso8601String(),
    );
    _commit(data.copyWith(bmis: [rec, ...data.bmis]));
  }

  void setPatient(String v) => _commit(data.copyWith(patient: v));
  void setSize(String v) => _commit(data.copyWith(size: v));
  void setNotify(bool v) => _commit(data.copyWith(notify: v));
  void setChannel(String v) => _commit(data.copyWith(notifyChannel: v));
  void setRepeat(bool v) => _commit(data.copyWith(repeatReminder: v));
  void setVerifiedPhone(String v) => _commit(data.copyWith(verifiedPhone: v));

  Future<void> resetAll() async {
    dismissed = <String>{};
    await _storage.clearPending(); // queued presses belong to the data being wiped
    _commit(AppData.seed(_clock()));
    await flush();
  }
}
