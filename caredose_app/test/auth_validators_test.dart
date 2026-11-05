import 'package:caredose/logic/auth_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeThaiMobile', () {
    test('accepts local and +66 forms', () {
      for (final raw in ['0812345678', '081-234-5678', '081 234 5678', '+66 81-234-5678', '66812345678']) {
        expect(normalizeThaiMobile(raw), '+66812345678', reason: raw);
      }
      expect(normalizeThaiMobile('0912345678'), '+66912345678');
      expect(normalizeThaiMobile('0612345678'), '+66612345678');
    });

    test('rejects landlines, wrong length, junk and empty', () {
      for (final raw in ['0212345678', '081234567', '08123456789', '12345', '', 'abc']) {
        expect(normalizeThaiMobile(raw), isNull, reason: raw);
      }
    });
  });

  test('displayPhone turns E.164 into a local number', () {
    expect(displayPhone('+66812345678'), '0812345678');
  });

  test('parseConditions splits, trims and de-duplicates', () {
    expect(parseConditions(' โรคกระเพาะ, ภูมิแพ้，โรคกระเพาะ,, '), ['โรคกระเพาะ', 'ภูมิแพ้']);
    expect(parseConditions('  '), <String>[]);
  });

  group('validateProfile', () {
    String? v({
      String nickname = 'สมศรี',
      String fullName = 'สมศรี ใจดี',
      String ageText = '65',
      List<String> conditions = const ['เบาหวาน'],
      bool consent = true,
    }) =>
        validateProfile(nickname: nickname, fullName: fullName, ageText: ageText, conditions: conditions, consent: consent);

    test('valid input passes', () => expect(v(), isNull));

    test('nickname', () {
      expect(v(nickname: '  '), 'กรุณากรอกชื่อเล่น');
      expect(v(nickname: 'ก' * 51), 'กรุณากรอกชื่อเล่น');
      expect(v(nickname: 'ก' * 50), isNull);
    });

    test('full name', () {
      expect(v(fullName: ''), 'กรุณากรอกชื่อ-นามสกุลจริง');
      expect(v(fullName: 'ก' * 101), 'กรุณากรอกชื่อ-นามสกุลจริง');
    });

    test('age', () {
      for (final a in ['', '0', '121', '25.5', 'abc', ' ']) {
        expect(v(ageText: a), 'กรุณากรอกอายุ 1–120 ปี', reason: a);
      }
      expect(v(ageText: '1'), isNull);
      expect(v(ageText: '120'), isNull);
    });

    test('conditions and consent', () {
      expect(v(conditions: []), 'กรุณาเลือกโรคประจำตัวหรือเลือกไม่มี');
      expect(v(conditions: [noConditions]), isNull);
      expect(v(consent: false), 'กรุณายินยอมให้เก็บข้อมูลสุขภาพก่อนบันทึก');
    });

    test('first error wins in field order', () {
      expect(v(nickname: '', fullName: '', ageText: '', conditions: [], consent: false), 'กรุณากรอกชื่อเล่น');
    });
  });

  test('commonConditions lists the six chips', () {
    expect(commonConditions, ['ความดันโลหิตสูง', 'เบาหวาน', 'โรคหัวใจ', 'ไขมันในเลือดสูง', 'โรคไต', 'หอบหืด']);
    expect(noConditions, 'ไม่มีโรคประจำตัว');
  });
}
