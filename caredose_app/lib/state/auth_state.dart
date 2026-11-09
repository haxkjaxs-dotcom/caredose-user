import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/profile.dart';
import '../services/auth_repository.dart';

enum AuthStatus { loading, loggedOut, needsProfile, ready, unavailable, notRegistered }

class AuthState extends ChangeNotifier {
  AuthState(
    this._repo,
    this._prefs, {
    this.onSignedIn,
    this.onSignedOut,
    this.beforeSignOut,
    this.beforeSignOutTimeout = const Duration(seconds: 5),
  });

  static const _cacheKey = 'caredose_profile';
  static const _ownerKey = 'caredose_owner'; // phone whose data lives on this device

  final AuthRepository _repo;
  final SharedPreferences _prefs;

  /// Fired after a fresh sign-in (OTP verified with a profile, or a profile just saved).
  final void Function(Profile p, String phoneE164)? onSignedIn;
  final VoidCallback? onSignedOut;

  /// Awaited (at most [beforeSignOutTimeout]) at the start of [signOut], while the session is still valid
  /// (the outbox flush hooks in here). Its failure or timeout never blocks signing out.
  final Future<void> Function()? beforeSignOut;
  final Duration beforeSignOutTimeout;

  AuthStatus status = AuthStatus.loading;
  Profile? profile;

  /// Extra message for the not-registered screen (e.g. duplicate phone); null = default text.
  String? notice;
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
    await _resolve();
  }

  /// Bumped by [signOut]; a [_resolve] started before it must not touch state afterwards.
  int _epoch = 0;

  /// Set by a fresh sign-in (OTP verified / retry) and kept until a resolve ends in a real answer,
  /// so [onSignedIn] still fires if the first attempt failed and was retried through [init].
  bool _pendingSignIn = false;

  /// Claims the patient row by phone, then loads the profile.
  Future<void> _resolve() async {
    final epoch = _epoch;
    notice = null;
    try {
      final id = await _repo.claimPatient();
      if (epoch != _epoch) return;
      if (id == null) {
        _pendingSignIn = false;
        _set(AuthStatus.notRegistered);
        return;
      }
      final p = await _repo.loadProfile();
      if (epoch != _epoch) return;
      if (p == null) {
        _pendingSignIn = false;
        _set(AuthStatus.needsProfile);
        return;
      }
      await _writeCache(p);
      if (epoch != _epoch) return;
      final fire = _pendingSignIn;
      _pendingSignIn = false;
      _set(AuthStatus.ready, p: p);
      if (fire) onSignedIn?.call(p, _repo.phone ?? '');
    } on AuthFailure catch (f) {
      if (epoch != _epoch) return;
      if (f.kind == AuthFailureKind.duplicatePhone || f.kind == AuthFailureKind.rejected) {
        // A definitive server answer, not an outage: never fall back to the cache.
        _pendingSignIn = false;
        notice = f.message;
        _set(AuthStatus.notRegistered);
      } else if (_pendingSignIn) {
        // The code is already used up; the session exists. Offer a retry instead of a dead end.
        _set(AuthStatus.unavailable);
      } else {
        final cached = _readCache();
        _set(cached == null ? AuthStatus.unavailable : AuthStatus.ready, p: cached);
      }
    }
  }

  bool _retrying = false;

  /// "Try again" on the not-registered screen (e.g. after an admin added the number). One at a time.
  Future<void> retry() async {
    if (_retrying) return;
    _retrying = true;
    try {
      _pendingSignIn = true;
      await _resolve();
    } finally {
      _retrying = false;
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
    _pendingSignIn = true;
    await _resolve();
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
      await beforeSignOut?.call().timeout(beforeSignOutTimeout);
    } catch (e) {
      debugPrint('before sign out failed: $e');
    }
    _epoch++;
    _pendingSignIn = false;
    try {
      await _repo.signOut();
    } catch (e) {
      debugPrint('sign out failed on the backend: $e');
    }
    await _prefs.remove(_cacheKey);
    await _prefs.remove(_ownerKey);
    notice = null;
    _set(AuthStatus.loggedOut);
    onSignedOut?.call();
  }
}
