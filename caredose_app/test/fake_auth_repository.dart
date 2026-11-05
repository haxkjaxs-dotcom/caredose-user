import 'dart:async';

import 'package:caredose/models/profile.dart';
import 'package:caredose/services/auth_repository.dart';

final sampleProfile = Profile(
  nickname: 'สมศรี',
  fullName: 'สมศรี ใจดี',
  age: 65,
  conditions: const ['เบาหวาน'],
  consentAt: DateTime.utc(2026, 11, 5),
);

/// In-memory [AuthRepository] for tests. Set [failure] to make every call throw;
/// set [gate] to hold send/verify/save until the completer completes.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.signedIn = false, this.phoneValue = '+66812345678', this.stored});

  bool signedIn;
  String? phoneValue;
  Profile? stored;
  AuthFailure? failure;
  Completer<void>? gate;
  int sendCalls = 0, verifyCalls = 0, saveCalls = 0, signOutCalls = 0, loadCalls = 0;
  Profile? lastSaved;

  @override
  bool get isSignedIn => signedIn;

  @override
  String? get phone => phoneValue;

  Future<void> _wait() async {
    final g = gate;
    if (g != null) await g.future;
  }

  void _maybeThrow() {
    final f = failure;
    if (f != null) throw f;
  }

  @override
  Future<void> sendOtp(String e164) async {
    sendCalls++;
    await _wait();
    _maybeThrow();
  }

  @override
  Future<void> verifyOtp(String e164, String code) async {
    verifyCalls++;
    await _wait();
    _maybeThrow();
    signedIn = true;
  }

  @override
  Future<Profile?> loadProfile() async {
    loadCalls++;
    _maybeThrow();
    return stored;
  }

  @override
  Future<void> saveProfile(Profile p) async {
    saveCalls++;
    await _wait();
    _maybeThrow();
    stored = p;
    lastSaved = p;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _maybeThrow();
    signedIn = false;
  }
}
