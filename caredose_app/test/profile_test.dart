import 'package:caredose/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final p = Profile(
    nickname: 'สมศรี',
    fullName: 'สมศรี ใจดี',
    age: 65,
    conditions: const ['เบาหวาน', 'ภูมิแพ้'],
    consentAt: DateTime.utc(2026, 11, 5, 3, 0),
  );

  test('JSON uses the database column names and round-trips', () {
    final j = p.toJson();
    expect(j['full_name'], 'สมศรี ใจดี');
    expect(j['consent_at'], '2026-11-05T03:00:00.000Z');
    expect(Profile.fromJson(j).toJson(), j);
  });

  test('fromJson throws FormatException on missing or wrongly typed fields', () {
    expect(() => Profile.fromJson({}), throwsFormatException);
    expect(() => Profile.fromJson({...p.toJson(), 'age': 'x'}), throwsFormatException);
  });
}
