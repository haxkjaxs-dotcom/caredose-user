import 'package:caredose/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('doseActions are the three buttons in order with Thai labels', () {
    expect(doseActions(), [
      ('taken', 'ทานแล้ว'),
      ('notyet', 'ยังไม่ทาน'),
      ('skip', 'ยังไม่ได้ทาน'),
    ]);
  });
}
