import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notice.dart';
import 'auth_repository.dart';
import 'notice_repository.dart';
import 'notification_plan.dart' show notificationId;

const _shownKey = 'caredose_shown_notices';
const _shownCap = 100;

/// Brings admin messages to the patient: shows each new one once as a system notification and marks it read.
/// New rows arrive over Realtime while the app is open; [pull] picks up what arrived while it was closed.
class NoticeSync {
  NoticeSync(this._repo, this._display, this._prefs, {bool Function()? canPull})
      : _canPull = canPull ?? (() => true) {
    _shown.addAll(_prefs.getStringList(_shownKey) ?? const []);
  }

  final NoticeRepository _repo;
  final NoticeDisplay _display;
  final SharedPreferences _prefs;

  /// False while signed out: nothing is fetched, subscribed to or shown.
  final bool Function() _canPull;

  // Insertion-ordered so the oldest id is dropped first. An id is added BEFORE the first await in _handle, which is
  // what makes a Realtime insert and a pull that carry the same row show it only once.
  final LinkedHashSet<String> _shown = LinkedHashSet<String>();
  void Function()? _cancel;
  int _epoch = 0; // bumped by stop(); a pull that started before is stale and must not show anything

  Future<void> pull() async {
    if (!_canPull()) return;
    final epoch = _epoch;
    try {
      final unread = await _repo.fetchUnread();
      if (epoch != _epoch || !_canPull()) return;
      for (final n in unread) {
        await _handle(n);
      }
    } on AuthFailure {
      // Offline or signed out: try again on the next pull.
    } catch (e) {
      debugPrint('notice pull failed: $e');
    }
  }

  void start() {
    if (_cancel != null || !_canPull()) return;
    _cancel = _repo.subscribe((n) {
      if (_canPull()) _handle(n);
    });
  }

  void stop() {
    _cancel?.call();
    _cancel = null;
    _epoch++;
  }

  /// Sign-out: the next person must not inherit this one's history.
  Future<void> clearShown() async {
    _shown.clear();
    await _prefs.remove(_shownKey);
  }

  Future<List<Notice>> loadRecent([int limit = 30]) async {
    try {
      return await _repo.fetchRecent(limit);
    } on AuthFailure {
      return const [];
    }
  }

  // id -> a show() still in flight. A duplicate of that message waits for the same result instead of racing it.
  final Map<String, Future<bool>> _showing = {};

  Future<void> _handle(Notice n) async {
    final inFlight = _showing[n.id];
    if (inFlight == null && _shown.contains(n.id)) {
      await _markRead(n.id); // shown earlier; this is the retry after a markRead that failed offline
      return;
    }
    // The id is claimed synchronously (before the first await), so Realtime and pull never both show it.
    final shown = await (inFlight ?? (_showing[n.id] = _show(n)));
    if (shown) await _markRead(n.id);
  }

  /// Shows [n] once. If it could not be shown (plugin not ready), the id is forgotten and the message stays unread
  /// on the server, so the next pull tries again: marking it read would lose it for good.
  Future<bool> _show(Notice n) async {
    _shown.add(n.id);
    while (_shown.length > _shownCap) {
      _shown.remove(_shown.first);
    }
    var ok = false;
    try {
      await _prefs.setStringList(_shownKey, _shown.toList());
      ok = await _display.show(notificationId('notice|${n.id}', repeat: false), n.title, n.body);
    } catch (e) {
      debugPrint('showing notice ${n.id} failed: $e');
    }
    if (!ok) {
      _shown.remove(n.id);
      await _prefs.setStringList(_shownKey, _shown.toList());
    }
    _showing.remove(n.id);
    return ok;
  }

  Future<void> _markRead(String id) async {
    try {
      await _repo.markRead([id]);
    } on AuthFailure {
      // retried by the next pull
    } catch (e) {
      debugPrint('marking notice $id read failed: $e');
    }
  }
}
