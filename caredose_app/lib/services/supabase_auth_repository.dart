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
  return const AuthFailure(AuthFailureKind.unknown);
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
  Future<Profile?> loadProfile() => _guard(() async {
        final uid = _c.auth.currentUser?.id;
        if (uid == null) return null;
        final row = await _c.from('profiles').select().eq('id', uid).maybeSingle();
        return row == null ? null : Profile.fromJson(row);
      });

  @override
  Future<void> saveProfile(Profile p) => _guard(() async {
        final uid = _c.auth.currentUser?.id;
        if (uid == null) throw const AuthFailure(AuthFailureKind.unknown);
        await _c.from('profiles').upsert({
          'id': uid,
          ...p.toJson(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      });

  @override
  Future<void> signOut() => _guard(() => _c.auth.signOut());
}
