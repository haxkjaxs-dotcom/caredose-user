import 'dart:async';
import 'dart:io';

import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/services/supabase_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthApiException, AuthRetryableFetchException;

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

  test('Thai messages', () {
    expect(const AuthFailure(AuthFailureKind.invalidCode).message, 'รหัส OTP ไม่ถูกต้องหรือหมดอายุ');
    expect(const AuthFailure(AuthFailureKind.rateLimited).message, 'ขอรหัสบ่อยเกินไป กรุณารอสักครู่');
    expect(const AuthFailure(AuthFailureKind.network).message, 'ไม่มีอินเทอร์เน็ต กรุณาลองใหม่');
    expect(const AuthFailure(AuthFailureKind.unknown).message, 'เกิดข้อผิดพลาด กรุณาลองใหม่');
  });
}
