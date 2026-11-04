import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../logic/bmi.dart';
import '../logic/dose_items.dart';
import '../models/models.dart';
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
  AppState(this._storage, this._scheduler, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    now = _clock();
    data = _storage.load(now);
    dismissed = _storage.loadDismissed();
  }

  final Storage _storage;
  final NotificationScheduler _scheduler;
  final DateTime Function() _clock;
  late AppData data;
  late Set<String> dismissed;
  late DateTime now;
  Future<void> _last = Future.value();

  /// Completes when all pending saves and reschedules have finished.
  Future<void> flush() => _last;

  void _commit(AppData d) {
    data = d;
    notifyListeners();
    _persist();
  }

  void _persist() {
    final snapshot = data;
    final dis = {...dismissed};
    final at = now;
    _last = _last.then((_) async {
      await _storage.save(snapshot);
      await _storage.saveDismissed(dis);
      await _scheduler.reschedule(snapshot, dis, at);
    }).catchError((Object e) {
      debugPrint('persist/reschedule failed: $e');
    });
  }

  void tick() {
    now = _clock();
    notifyListeners();
  }

  /// Re-read storage (a notification button may have written to it from a
  /// background isolate). Replaces state and reschedules only if it changed.
  Future<void> reload() async {
    await flush();
    await _storage.refresh();
    now = _clock();
    final fresh = _storage.load(now);
    final freshDismissed = _storage.loadDismissed();
    if (jsonEncode(fresh.toJson()) == jsonEncode(data.toJson()) && setEquals(freshDismissed, dismissed)) {
      notifyListeners();
      return;
    }
    data = fresh;
    dismissed = freshDismissed;
    notifyListeners();
    await _scheduler.reschedule(data, dismissed, now);
  }

  /// Handles a notification button pressed while the app process is alive.
  Future<void> applyNotificationAction(String actionId, String key) async {
    final r = applyDoseAction(data, dismissed, actionId, key, _clock());
    dismissed = r.dismissed;
    _commit(r.data);
    await flush();
  }

  void _setLog(String key, DoseStatus s) {
    final logs = {...data.logs, key: DoseLog(s == DoseStatus.skipped ? 'skipped' : 'taken', _clock().toIso8601String())};
    _commit(data.copyWith(logs: logs));
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
    return due.map((e) => e.key).toList();
  }

  void undoKeys(List<String> keys) {
    final logs = {...data.logs}..removeWhere((k, _) => keys.contains(k));
    _commit(data.copyWith(logs: logs));
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
    _commit(AppData.seed(_clock()));
    await flush();
  }
}
