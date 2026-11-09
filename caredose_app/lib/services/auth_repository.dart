import '../models/profile.dart';

enum AuthFailureKind { invalidCode, rateLimited, network, duplicatePhone, rejected, unknown }

/// The only error type [AuthRepository] methods throw.
class AuthFailure implements Exception {
  const AuthFailure(this.kind);
  final AuthFailureKind kind;

  String get message {
    switch (kind) {
      case AuthFailureKind.invalidCode:
        return 'รหัส OTP ไม่ถูกต้องหรือหมดอายุ';
      case AuthFailureKind.rateLimited:
        return 'ขอรหัสบ่อยเกินไป กรุณารอสักครู่';
      case AuthFailureKind.network:
        return 'ไม่มีอินเทอร์เน็ต กรุณาลองใหม่';
      case AuthFailureKind.duplicatePhone:
        return 'เบอร์นี้ซ้ำในระบบ กรุณาติดต่อผู้ดูแล';
      case AuthFailureKind.rejected:
        return 'ระบบไม่อนุญาตการทำรายการนี้';
      case AuthFailureKind.unknown:
        return 'เกิดข้อผิดพลาด กรุณาลองใหม่';
    }
  }

  @override
  String toString() => 'AuthFailure($kind)';
}

abstract class AuthRepository {
  bool get isSignedIn;

  /// E.164 phone of the signed-in user (`+66…`), or null.
  String? get phone;

  Future<void> sendOtp(String e164);
  Future<void> verifyOtp(String e164, String code);

  /// Links the signed-in account to the patient an admin registered with this phone.
  /// Returns the patient id, or null when no such patient exists (yet).
  Future<String?> claimPatient();
  Future<Profile?> loadProfile();
  Future<void> saveProfile(Profile p);
  Future<void> signOut();
}
