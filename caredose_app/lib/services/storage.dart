import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class Storage {
  Storage(this._p);
  final SharedPreferences _p;

  static const _key = 'caredose';
  static const _dismissedKey = 'caredose_dismissed';

  /// Re-reads values written by another isolate (notification button handler).
  Future<void> refresh() => _p.reload();

  /// Reads saved data merged over the seed; any unreadable value yields the seed.
  AppData load(DateTime now) {
    final seed = AppData.seed(now);
    final raw = _p.getString(_key);
    if (raw == null) return seed;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return seed;
      return AppData.fromJson({...seed.toJson(), ...Json.from(decoded)});
    } catch (_) {
      return seed;
    }
  }

  Future<void> save(AppData d) => _p.setString(_key, jsonEncode(d.toJson()));

  /// Button presses recorded by the background isolate as tab-separated `action, doseKey, iso`.
  /// Only AppState writes the main data; it drains these so nothing is overwritten.
  static const _pendingKey = 'caredose_pending';

  List<String> loadPending() => _p.getStringList(_pendingKey) ?? const <String>[];

  Future<void> appendPending(String entry) async {
    await _p.reload();
    await _p.setStringList(_pendingKey, [...loadPending(), entry]);
  }

  /// Removes the first [count] entries (entries are only ever appended meanwhile).
  Future<void> removePending(int count) async {
    await _p.reload();
    await _p.setStringList(_pendingKey, loadPending().skip(count).toList());
  }

  Set<String> loadDismissed() => (_p.getStringList(_dismissedKey) ?? const <String>[]).toSet();

  Future<void> saveDismissed(Set<String> s) => _p.setStringList(_dismissedKey, s.toList());
}
