import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.text('ตั้งค่า').first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('choosing the largest font size updates the setting', (tester) async {
    final s = await pumpApp(tester);
    await openSettings(tester);
    await tapVisible(tester, find.text('ใหญ่มาก'));
    expect(s.data.size, 'xl');
    await disposeApp(tester);
  });

  testWidgets('turning notifications off saves and reschedules', (tester) async {
    final s = await pumpApp(tester);
    await openSettings(tester);
    final before = lastScheduler.calls;
    await tapVisible(tester, find.byKey(const ValueKey('notify-switch')));
    await s.flush();
    expect(s.data.notify, false);
    expect(lastScheduler.calls, before + 1);
    await disposeApp(tester);
  });

  testWidgets('phone change validates phone and OTP before saving', (tester) async {
    final s = await pumpApp(tester);
    await openSettings(tester);
    await tapVisible(tester, find.text('เปลี่ยนเบอร์และยืนยัน OTP'));
    await tester.enterText(find.byKey(const ValueKey('new-phone')), '081');
    await tapVisible(tester, find.text('ส่งรหัส OTP'));
    expect(find.text('กรุณากรอกเบอร์โทรศัพท์ให้ถูกต้อง'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('new-phone')), '0899999999');
    await tapVisible(tester, find.text('ส่งรหัส OTP'));
    expect(find.text('ส่งรหัส OTP ไปยัง 0899999999 แล้ว'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('otp')), '12');
    await tapVisible(tester, find.text('ยืนยันและใช้เบอร์นี้'));
    expect(find.text('กรุณากรอกรหัส OTP 6 หลัก'), findsOneWidget);
    expect(s.data.verifiedPhone, '081-234-5678');

    await tester.enterText(find.byKey(const ValueKey('otp')), '123456');
    await tapVisible(tester, find.text('ยืนยันและใช้เบอร์นี้'));
    expect(s.data.verifiedPhone, '0899999999');
    await disposeApp(tester);
  });

  testWidgets('permission banner shows when system notifications are off', (tester) async {
    final perms = FakePermissions(granted: false);
    await pumpApp(tester, permissions: perms);
    await openSettings(tester);
    expect(find.text('การแจ้งเตือนของเครื่องยังปิดอยู่'), findsOneWidget);
    await tapVisible(tester, find.text('อนุญาตการแจ้งเตือน'));
    expect(perms.requests, 1);
    expect(find.text('การแจ้งเตือนของเครื่องยังปิดอยู่'), findsNothing);
    await disposeApp(tester);
  });

  testWidgets('no banner when permission is granted', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);
    expect(find.text('การแจ้งเตือนของเครื่องยังปิดอยู่'), findsNothing);
    await disposeApp(tester);
  });

  testWidgets('clear data asks for confirmation and restores the sample data', (tester) async {
    final s = await pumpApp(tester);
    s.setPatient('คนอื่น');
    await tester.pumpAndSettle();
    await openSettings(tester);
    await tapVisible(tester, find.text('จัดการข้อมูลในเครื่อง: ล้างข้อมูล'));
    expect(find.text('ลบข้อมูลทั้งหมดในเครื่อง และเริ่มใหม่ด้วยข้อมูลตัวอย่าง?'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('ลบ')));
    await tester.pumpAndSettle();
    expect(s.data.patient, 'คุณแม่สมศรี');
    await disposeApp(tester);
  });
}
