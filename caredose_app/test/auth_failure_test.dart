import 'dart:async';
import 'dart:io';

import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/services/supabase_auth_repository.dart';
import 'package:caredose/services/supabase_med_repository.dart' show requireUserId;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthApiException, AuthRetryableFetchException, PostgrestException;

void main() {
  AuthFailureKind kind(Object e) => mapAuthError(e).kind;

  test('wrong or expired code', () {
    expect(kind(const AuthApiException('Token has expired or is invalid', statusCode: '403', code: 'otp_expired')), AuthFailureKind.invalidCode);
    expect(kind(const AuthApiException('Token has expired or is invalid', statusCode: '403')), AuthFailureKind.invalidCode);
  });

  test('rate limiting', () {
    expect(kind(const AuthApiException('x', statusCode: '429', code: 'over_sms_send_rate_limit')), AuthFailureKind.rateLimited);
    expect(kind(const AuthApiException('x', statusCode: '429')), AuthFailureKind.rateLimited);
  });

  test('network problems', () {
    expect(kind(const SocketException('x')), AuthFailureKind.network);
    expect(kind(TimeoutException('x')), AuthFailureKind.network);
    expect(kind(AuthRetryableFetchException()), AuthFailureKind.network);
  });

  test('anything else is unknown; AuthFailure passes through', () {
    expect(kind(StateError('x')), AuthFailureKind.unknown);
    const f = AuthFailure(AuthFailureKind.network);
    expect(identical(mapAuthError(f), f), true);
  });

  test('duplicate phone and rejected account from the database', () {
    expect(kind(PostgrestException(message: 'เบอร์ซ้ำในระบบ', code: 'P0001')), AuthFailureKind.duplicatePhone);
    expect(kind(PostgrestException(message: 'other', code: 'P0001')), AuthFailureKind.unknown);
    expect(kind(PostgrestException(message: 'not allowed', code: '42501')), AuthFailureKind.rejected);
  });

  test('data and constraint errors from the database are rejected; other server errors stay unknown', () {
    for (final code in ['23503', '23514', '22P02', '23505', '22007']) {
      expect(kind(PostgrestException(message: 'bad', code: code)), AuthFailureKind.rejected, reason: code);
    }
    expect(kind(PostgrestException(message: 'x', code: 'PGRST301')), AuthFailureKind.unknown);
    expect(kind(PostgrestException(message: 'x')), AuthFailureKind.unknown);
  });

  test('a server outage is a network failure, never unknown', () {
    expect(kind(PostgrestException(message: '<html>Bad Gateway</html>', code: '502')), AuthFailureKind.network);
    expect(kind(PostgrestException(message: 'x', code: '500')), AuthFailureKind.network);
    expect(kind(PostgrestException(message: '<!DOCTYPE html><html>', code: 'PGRST000')), AuthFailureKind.network);
    expect(kind(PostgrestException(message: 'x', code: '57P03')), AuthFailureKind.network); // db starting up
    expect(kind(const FormatException('Unexpected character')), AuthFailureKind.network);
    expect(kind(const AuthApiException('x', statusCode: '503')), AuthFailureKind.network);
    expect(kind(http.ClientException('connection closed')), AuthFailureKind.network);
    // permanent business errors keep their meaning, and plain unknowns stay unknown
    expect(kind(const AuthApiException('x', statusCode: '403', code: 'otp_expired')), AuthFailureKind.invalidCode);
    expect(kind(PostgrestException(message: 'x', code: '23503')), AuthFailureKind.rejected);
    expect(kind(PostgrestException(message: 'x', code: 'PGRST301')), AuthFailureKind.unknown);
  });

  group('guardCall', () {
    test('a call that never finishes becomes a network failure after the timeout', () async {
      await expectLater(
        guardCall(() => Completer<int>().future, timeout: const Duration(milliseconds: 30)),
        throwsA(isA<AuthFailure>().having((f) => f.kind, 'kind', AuthFailureKind.network)),
      );
    });

    test('returns the value and maps errors like mapAuthError', () async {
      expect(await guardCall(() async => 7), 7);
      await expectLater(guardCall<void>(() async => throw const SocketException('x')), throwsA(isA<AuthFailure>().having((f) => f.kind, 'kind', AuthFailureKind.network)));
      await expectLater(
        guardCall<void>(() async => throw PostgrestException(message: 'fk', code: '23503')),
        throwsA(isA<AuthFailure>().having((f) => f.kind, 'kind', AuthFailureKind.rejected)),
      );
    });
  });

  test('a missing signed-in user keeps queued records (network), it does not reject them', () {
    expect(requireUserId('u1'), 'u1');
    expect(() => requireUserId(null), throwsA(isA<AuthFailure>().having((f) => f.kind, 'kind', AuthFailureKind.network)));
  });

  test('patients row to Profile', () {
    final row = {
      'nickname': 'สมศรี',
      'full_name': 'สมศรี ใจดี',
      'age': 65,
      'conditions': 'เบาหวาน, ความดันโลหิตสูง',
      'profile_completed_at': '2026-11-09T01:00:00+00:00',
    };
    final p = profileFromPatientRow(row)!;
    expect(p.conditions, ['เบาหวาน', 'ความดันโลหิตสูง']);
    expect(p.consentAt.toUtc(), DateTime.utc(2026, 11, 9, 1));
    expect(profileFromPatientRow({...row, 'profile_completed_at': null}), isNull);
    expect(profileFromPatientRow(null), isNull);
    expect(profileFromPatientRow({...row, 'conditions': null})!.conditions, isEmpty);
  });

  test('Thai messages', () {
    expect(const AuthFailure(AuthFailureKind.duplicatePhone).message, 'เบอร์นี้ซ้ำในระบบ กรุณาติดต่อผู้ดูแล');
    expect(const AuthFailure(AuthFailureKind.rejected).message, 'ระบบไม่อนุญาตการทำรายการนี้');
    expect(const AuthFailure(AuthFailureKind.invalidCode).message, 'รหัส OTP ไม่ถูกต้องหรือหมดอายุ');
    expect(const AuthFailure(AuthFailureKind.rateLimited).message, 'ขอรหัสบ่อยเกินไป กรุณารอสักครู่');
    expect(const AuthFailure(AuthFailureKind.network).message, 'ไม่มีอินเทอร์เน็ต กรุณาลองใหม่');
    expect(const AuthFailure(AuthFailureKind.unknown).message, 'เกิดข้อผิดพลาด กรุณาลองใหม่');
  });
}
