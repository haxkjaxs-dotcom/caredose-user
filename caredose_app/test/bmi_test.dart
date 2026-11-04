import 'package:caredose/logic/bmi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bmiValue rounds to one decimal', () {
    expect(bmiValue(58, 155), 24.1);
  });

  test('bmiCategory boundaries', () {
    expect(bmiCategory(18.4), 'ต่ำกว่าเกณฑ์');
    expect(bmiCategory(18.5), 'ปกติ');
    expect(bmiCategory(24.9), 'ปกติ');
    expect(bmiCategory(25), 'สูงกว่าเกณฑ์');
  });

  test('validateBmiInput', () {
    const msg = 'กรุณากรอกน้ำหนัก (กก.) และส่วนสูง (ซม.) ให้ถูกต้อง';
    expect(validateBmiInput(58, 155), isNull);
    expect(validateBmiInput(0, 155), msg);
    expect(validateBmiInput(58, 49), msg);
    expect(validateBmiInput(400, 155), msg);
    expect(validateBmiInput(58, 250), msg);
    expect(validateBmiInput(null, 155), msg);
    expect(validateBmiInput(58, null), msg);
    expect(validateBmiInput(double.nan, 155), msg);
  });
}
