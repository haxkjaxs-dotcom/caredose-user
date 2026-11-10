import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import 'auth_repository.dart';

/// Maps any exception from Supabase / the network to an [AuthFailure].
AuthFailure mapAuthError(Object e) {
  if (e is AuthFailure) return e;
  if (e is AuthRetryableFetchException || e is SocketException || e is TimeoutException || e is http.ClientException) {
    return const AuthFailure(AuthFailureKind.network);
  }
  if (e is AuthException) {
    final code = e.code ?? '';
    if (code == 'over_sms_send_rate_limit' || code == 'over_request_rate_limit' || e.statusCode == '429') {
      return const AuthFailure(AuthFailureKind.rateLimited);
    }
    if (code == 'otp_expired' || code == 'otp_disabled' || code == 'validation_failed' || e.message.contains('Token has expired or is invalid')) {
      return const AuthFailure(AuthFailureKind.invalidCode);
    }
  }
  if (e is PostgrestException) {
    if (e.code == 'P0001' && e.message.contains('เบอร์ซ้ำ')) return const AuthFailure(AuthFailureKind.duplicatePhone);
    if (e.code == '42501') return const AuthFailure(AuthFailureKind.rejected);
    // Data (22xxx) and constraint (23xxx) errors: retrying the same payload can never succeed.
    final c = e.code ?? '';
    if (c.startsWith('22') || c.startsWith('23')) return const AuthFailure(AuthFailureKind.rejected);
  }
  return const AuthFailure(AuthFailureKind.unknown);
}

/// A `patients` row as a [Profile]; null until the patient has completed onboarding.
Profile? profileFromPatientRow(Map<String, dynamic>? row) {
  final done = row?['profile_completed_at'];
  if (row == null || done == null) return null;
  final conditions = (row['conditions'] as String? ?? '').split(',').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
  return Profile.fromJson({...row, 'conditions': conditions, 'consent_at': done});
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._c);
  final SupabaseClient _c;

  @override
  bool get isSignedIn => _c.auth.currentSession != null;

  @override
  String? get phone {
    final p = _c.auth.currentUser?.phone;
    if (p == null || p.isEmpty) return null;
    return p.startsWith('+') ? p : '+$p';
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw mapAuthError(e);
    }
  }

  @override
  Future<void> sendOtp(String e164) => _guard(() => _c.auth.signInWithOtp(phone: e164));

  @override
  Future<void> verifyOtp(String e164, String code) =>
      _guard(() => _c.auth.verifyOTP(phone: e164, token: code, type: OtpType.sms));

  @override
  Future<String?> claimPatient() => _guard(() async => (await _c.rpc('claim_my_patient')) as String?);

  @override
  Future<Profile?> loadProfile() => _guard(() async {
        final uid = _c.auth.currentUser?.id;
        if (uid == null) return null;
        final row = await _c
            .from('patients')
            .select('nickname, full_name, age, conditions, profile_completed_at')
            .eq('user_id', uid)
            .maybeSingle();
        return profileFromPatientRow(row);
      });

  @override
  Future<void> saveProfile(Profile p) => _guard(() async {
        await _c.rpc('save_my_profile', params: {
          'p_nickname': p.nickname,
          'p_full_name': p.fullName,
          'p_age': p.age,
          'p_conditions': p.conditions,
          'p_consent_version': '2026-11',
        });
      });

  @override
  Future<void> signOut() => _guard(() => _c.auth.signOut());
}
