import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/profile.dart';
import '../services/auth_repository.dart';

enum AuthStatus { loading, loggedOut, needsProfile, ready, unavailable }

class AuthState extends ChangeNotifier {
  AuthState(this._repo, this._prefs, {this.onSignedIn, this.onSignedOut});

  static const _cacheKey = 'caredose_profile';
  static const _ownerKey = 'caredose_owner'; // phone whose data lives on this device

  final AuthRepository _repo;
  final SharedPreferences _prefs;

  /// Fired after a fresh sign-in (OTP verified with a profile, or a profile just saved).
  final void Function(Profile p, String phoneE164)? onSignedIn;
  final VoidCallback? onSignedOut;

  AuthStatus status = AuthStatus.loading;
  Profile? profile;
  String? get phoneE164 => _repo.phone;

  void _set(AuthStatus s, {Profile? p}) {
    status = s;
    profile = p;
    notifyListeners();
  }

  Profile? _readCache() {
    final raw = _prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      return Profile.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(Profile p) => _prefs.setString(_cacheKey, jsonEncode(p.toJson()));

  /// Decides the status from the saved session. A restored session does not fire [onSignedIn].
  Future<void> init() async {
    if (!_repo.isSignedIn) {
      _set(AuthStatus.loggedOut);
      return;
    }
    try {
      final p = await _repo.loadProfile();
      if (p == null) {
        _set(AuthStatus.needsProfile);
      } else {
        await _writeCache(p);
        _set(AuthStatus.ready, p: p);
      }
    } on AuthFailure {
      final cached = _readCache();
      _set(cached == null ? AuthStatus.unavailable : AuthStatus.ready, p: cached);
    }
  }

  Future<void> sendOtp(String e164) => _repo.sendOtp(e164);

  Future<void> verifyOtp(String e164, String code) async {
    await _repo.verifyOtp(e164, code);
    final phone = _repo.phone ?? e164;
    final owner = _prefs.getString(_ownerKey);
    if (owner != null && owner != phone) {
      // Another person's data is still on this device (their session ended without a sign-out).
      await _prefs.remove(_cacheKey);
      onSignedOut?.call();
    }
    await _prefs.setString(_ownerKey, phone);
    final Profile? p;
    try {
      p = await _repo.loadProfile();
    } on AuthFailure {
      // The code is already used up; the session exists. Offer a retry instead of a dead end.
      _set(AuthStatus.unavailable);
      return;
    }
    if (p == null) {
      _set(AuthStatus.needsProfile);
    } else {
      await _writeCache(p);
      _set(AuthStatus.ready, p: p);
      onSignedIn?.call(p, _repo.phone ?? e164);
    }
  }

  Future<void> saveProfile(Profile p) async {
    await _repo.saveProfile(p);
    await _writeCache(p);
    _set(AuthStatus.ready, p: p);
    onSignedIn?.call(p, _repo.phone ?? '');
  }

  /// Always ends logged out and clears local data, even if the backend call fails.
  Future<void> signOut() async {
    try {
      await _repo.signOut();
    } catch (e) {
      debugPrint('sign out failed on the backend: $e');
    }
    await _prefs.remove(_cacheKey);
    await _prefs.remove(_ownerKey);
    _set(AuthStatus.loggedOut);
    onSignedOut?.call();
  }
}
