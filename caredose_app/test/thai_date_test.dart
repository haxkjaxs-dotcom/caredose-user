import 'package:caredose/logic/thai_date.dart';
import 'package:caredose/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('thDate formats weekday, day, month and Buddhist year', () {
    expect(thDate('2026-11-04'), 'วันพุธที่ 4 พฤศจิกายน 2569');
  });

  test('thDateShort uses abbreviated month', () {
    expect(thDateShort('2026-01-09'), '9 ม.ค. 2569');
  });

  test('thMonthYear formats month and Buddhist year', () {
    expect(thMonthYear(2026, 11), 'พฤศจิกายน 2569');
  });

  test('thTime pads to two digits', () {
    expect(thTime(DateTime(2026, 1, 1, 8, 5)), '08:05');
  });

  test('dateKey pads month and day', () {
    expect(dateKey(DateTime(2026, 3, 7)), '2026-03-07');
    expect(todayKey(DateTime(2026, 12, 31, 23, 59)), '2026-12-31');
  });

  test('textScaleFor maps size names', () {
    expect(textScaleFor('normal'), 1.0);
    expect(textScaleFor('large'), 1.25);
    expect(textScaleFor('xl'), 1.5);
    expect(textScaleFor('unknown'), 1.0);
  });
}
