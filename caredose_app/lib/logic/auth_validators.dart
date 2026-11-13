const commonConditions = ['ความดันโลหิตสูง', 'เบาหวาน', 'โรคหัวใจ', 'ไขมันในเลือดสูง', 'โรคไต', 'หอบหืด'];
const noConditions = 'ไม่มีโรคประจำตัว';

/// Thai mobile number -> `+66XXXXXXXXX`, or null when it is not a valid 10-digit 06/08/09 mobile.
String? normalizeThaiMobile(String raw) {
  var s = raw.replaceAll(RegExp(r'[^0-9+]'), '');
  if (s.startsWith('+66')) {
    s = '0${s.substring(3)}';
  } else if (s.startsWith('66')) {
    s = '0${s.substring(2)}';
  }
  if (!RegExp(r'^0[689]\d{8}$').hasMatch(s)) return null;
  return '+66${s.substring(1)}';
}

/// `+66812345678` -> `0812345678`.
String displayPhone(String e164) => e164.startsWith('+66') ? '0${e164.substring(3)}' : e164;

/// Splits on `,` / `，`, trims, drops empties and duplicates (order kept).
List<String> parseConditions(String custom) {
  final seen = <String>{};
  return [
    for (final part in custom.split(RegExp(r'[,，]')).map((e) => e.trim()))
      if (part.isNotEmpty && seen.add(part)) part,
  ];
}

/// Same limits as `save_my_relative` on the server (name 1-100, relationship up to 50, phone 1-20 characters).
/// Returns the first error message, or null when the relative may be sent.
String? validateRelative({required String name, required String rel, required String phone}) {
  if (name.trim().isEmpty || phone.trim().isEmpty) return 'กรุณากรอกชื่อและเบอร์โทร';
  if (name.trim().length > 100) return 'ชื่อต้องไม่เกิน 100 ตัวอักษร';
  if (rel.trim().length > 50) return 'ความสัมพันธ์ต้องไม่เกิน 50 ตัวอักษร';
  if (phone.trim().length > 20) return 'เบอร์โทรต้องไม่เกิน 20 ตัว';
  return null;
}

/// First error message in field order, or null when the profile may be saved.
String? validateProfile({
  required String nickname,
  required String fullName,
  required String ageText,
  required List<String> conditions,
  required bool consent,
}) {
  final nick = nickname.trim();
  if (nick.isEmpty || nick.length > 50) return 'กรุณากรอกชื่อเล่น';
  final name = fullName.trim();
  if (name.isEmpty || name.length > 100) return 'กรุณากรอกชื่อ-นามสกุลจริง';
  final age = int.tryParse(ageText.trim());
  if (age == null || age < 1 || age > 120) return 'กรุณากรอกอายุ 1–120 ปี';
  if (conditions.isEmpty) return 'กรุณาเลือกโรคประจำตัวหรือเลือกไม่มี';
  if (!consent) return 'กรุณายินยอมให้เก็บข้อมูลสุขภาพก่อนบันทึก';
  return null;
}
