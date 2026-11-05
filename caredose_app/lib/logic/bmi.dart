const bmiInputError = 'กรุณากรอกน้ำหนัก (กก.) และส่วนสูง (ซม.) ให้ถูกต้อง';

/// Returns null when valid, otherwise the Thai error message.
String? validateBmiInput(double? w, double? h) {
  if (w == null || h == null || w.isNaN || h.isNaN) return bmiInputError;
  if (!(w > 0 && w < 400) || !(h > 50 && h < 250)) return bmiInputError;
  return null;
}

double bmiValue(double w, double h) {
  final m = h / 100;
  return (w / (m * m) * 10).round() / 10;
}

String bmiCategory(double v) => v < 18.5 ? 'ต่ำกว่าเกณฑ์' : (v < 25 ? 'ปกติ' : 'สูงกว่าเกณฑ์');
