import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import 'auth_repository.dart';

/// Maps any exception from Supabase / the network to an [AuthFailure].
AuthFailure mapAuthError(Object e) {
  if (e is AuthFailure) return e;
  if (e is AuthRetryableFetchException || e is SocketException || e is TimeoutException || e is http.ClientException || e is FormatException) {
    return const AuthFailure(AuthFailureKind.network);
  }
  if (e is AuthException) {
    final code = e.code ?? '';
    if ((int.tryParse(e.statusCode ?? '') ?? 0) >= 500) return const AuthFailure(AuthFailureKind.network);
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
    // Server unreachable or unhealthy (5xx, class 53/57/58 SQLSTATEs, an HTML gateway page): transient, never counts against an entry.
    if (c.startsWith('5') || e.message.trimLeft().startsWith('<')) return const AuthFailure(AuthFailureKind.network);
  }
  return const AuthFailure(AuthFailureKind.unknown);
}

/// Runs a network call with a timeout (a half-open socket would otherwise hang the caller forever)
/// and turns every error into an [AuthFailure].
Future<T> guardCall<T>(Future<T> Function() run, {Duration timeout = const Duration(seconds: 20)}) async {
  try {
    return await run().timeout(timeout);
  } catch (e) {
    throw mapAuthError(e);
  }
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

  @override
  Future<void> sendOtp(String e164) => guardCall(() => _c.auth.signInWithOtp(phone: e164));

  @override
  Future<void> verifyOtp(String e164, String code) =>
      guardCall(() => _c.auth.verifyOTP(phone: e164, token: code, type: OtpType.sms));

  @override
  Future<String?> claimPatient() => guardCall(() async => (await _c.rpc('claim_my_patient')) as String?);

  @override
  Future<Profile?> loadProfile() => guardCall(() async {
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
  Future<void> saveProfile(Profile p) => guardCall(() async {
        await _c.rpc('save_my_profile', params: {
          'p_nickname': p.nickname,
          'p_full_name': p.fullName,
          'p_age': p.age,
          'p_conditions': p.conditions,
          'p_consent_version': '2026-11',
        });
      });

  @override
  Future<void> signOut() => guardCall(() => _c.auth.signOut());
}
