import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class Storage {
  Storage(this._p);
  final SharedPreferences _p;

  static const _key = 'caredose';
  static const _dismissedKey = 'caredose_dismissed';

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

  Set<String> loadDismissed() => (_p.getStringList(_dismissedKey) ?? const <String>[]).toSet();

  Future<void> saveDismissed(Set<String> s) => _p.setStringList(_dismissedKey, s.toList());
}
