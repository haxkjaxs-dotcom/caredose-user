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

  /// Only [loadProfile] throws this (e.g. the network drops right after the code is accepted).
  AuthFailure? loadFailure;
  Completer<void>? gate;

  /// What [claimPatient] returns (null = phone not registered by an admin yet).
  String? claimResult = 'patient-1';

  /// Only [claimPatient] throws this (e.g. duplicate phone).
  AuthFailure? claimFailure;

  /// When set, [claimPatient] waits for it (to test concurrent retries).
  Completer<void>? claimGate;
  int sendCalls = 0, verifyCalls = 0, saveCalls = 0, signOutCalls = 0, loadCalls = 0, claimCalls = 0;
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
  Future<String?> claimPatient() async {
    claimCalls++;
    final g = claimGate;
    if (g != null) await g.future;
    final cf = claimFailure;
    if (cf != null) throw cf;
    _maybeThrow();
    return claimResult;
  }

  @override
  Future<Profile?> loadProfile() async {
    loadCalls++;
    final lf = loadFailure;
    if (lf != null) throw lf;
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
