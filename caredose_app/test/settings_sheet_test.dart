import 'package:caredose/models/remote_plan.dart';
import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/state/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_notice_repository.dart';
import 'helpers.dart';

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.text('ตั้งค่า').first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the settings sheet opens the admin message inbox', (tester) async {
    await pumpApp(tester);
    lastNoticeRepo.recent = [notice('1', title: 'นัดตรวจพรุ่งนี้', body: 'มาก่อน 9 โมง')];
    await openSettings(tester);
    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'ข้อความจากผู้ดูแล'));
    expect(find.text('นัดตรวจพรุ่งนี้'), findsOneWidget);
    expect(find.text('มาก่อน 9 โมง'), findsOneWidget);
    await disposeApp(tester);
  });

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

  testWidgets('the verified phone is shown read-only (no mock number change)', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);
    expect(find.text('เบอร์รับ SMS ที่ยืนยันแล้ว'), findsOneWidget);
    expect(find.textContaining('เบอร์ที่ใช้เข้าสู่ระบบ'), findsOneWidget);
    expect(find.text('เปลี่ยนเบอร์และยืนยัน OTP'), findsNothing);
    await disposeApp(tester);
  });

  testWidgets('about text no longer claims there is no account', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);
    await tapVisible(tester, find.text('เกี่ยวกับแอป'));
    expect(find.textContaining('ไม่มีระบบบัญชี'), findsNothing);
    expect(find.textContaining('ประวัติการทานยาเก็บในเครื่องนี้'), findsNothing);
    expect(find.textContaining('ข้อมูลยา ประวัติการทานยา และข้อมูลส่วนตัวถูกเก็บในระบบหลังเข้าสู่ระบบด้วยเบอร์โทร และมีสำเนาในเครื่องนี้ไว้ใช้ตอนไม่มีอินเทอร์เน็ต'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('sign out asks first, then signs out and wipes local data', (tester) async {
    final s = await pumpApp(tester);
    s.setPatient('คนอื่น');
    await tester.pumpAndSettle();
    await openSettings(tester);
    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'ออกจากระบบ'));
    expect(find.text('ออกจากระบบ? ข้อมูลยาและประวัติในเครื่องนี้จะถูกล้างด้วย'), findsOneWidget);

    // cancelling changes nothing
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('ยกเลิก')));
    await tester.pumpAndSettle();
    expect(lastAuth.status, AuthStatus.ready);
    expect(s.data.patient, 'คนอื่น');

    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'ออกจากระบบ'));
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('ออกจากระบบ')));
    await tester.pumpAndSettle();
    expect(lastAuthRepo.signOutCalls, 1);
    expect(lastAuth.status, AuthStatus.loggedOut);
    expect(s.data.patient, '');
    expect(find.text('ส่งรหัส OTP'), findsOneWidget); // back at the login screen
    await disposeApp(tester);
  });

  final queued = LogOp(planId: 'p1', scheduleId: 's1', status: 'taken', scheduledAt: DateTime.utc(2026, 11, 4, 1), takenAt: DateTime.utc(2026, 11, 4, 1, 5));
  const warning = 'บันทึกการทานยาที่ยังส่งไม่ได้จะหายไป';

  testWidgets('sign-out dialog has no unsent-records warning when the outbox is empty', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);
    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'ออกจากระบบ'));
    expect(find.text(warning), findsNothing);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('ยกเลิก')));
    await tester.pumpAndSettle();
    await disposeApp(tester);
  });

  testWidgets('sign-out dialog warns about unsent records; confirming flushes first, then empties the outbox', (tester) async {
    await pumpApp(tester);
    lastMedRepo.onUpsert = (_) async => throw const AuthFailure(AuthFailureKind.network); // offline: it cannot be sent
    await lastOutbox.add(queued);
    await openSettings(tester);
    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'ออกจากระบบ'));
    expect(find.text(warning), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('ออกจากระบบ')));
    await tester.pumpAndSettle();
    expect(lastMedRepo.upsertCalls, 1); // flush was tried before leaving
    expect(lastAuthRepo.signOutCalls, 1);
    expect(lastOutbox.pendingCount, 0);
    expect(lastAuth.status, AuthStatus.loggedOut);
    await disposeApp(tester);
  });

  testWidgets('signing out while online sends the queued record before leaving', (tester) async {
    await pumpApp(tester);
    await lastOutbox.add(queued);
    await openSettings(tester);
    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'ออกจากระบบ'));
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('ออกจากระบบ')));
    await tester.pumpAndSettle();
    expect(lastMedRepo.upserts.single.scheduleId, 's1');
    expect(lastOutbox.pendingCount, 0);
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

  testWidgets('clear data asks for confirmation and restores the empty defaults', (tester) async {
    final s = await pumpApp(tester);
    s.setPatient('คนอื่น');
    await tester.pumpAndSettle();
    await openSettings(tester);
    await tapVisible(tester, find.text('จัดการข้อมูลในเครื่อง: ล้างข้อมูล'));
    expect(find.text('ลบข้อมูลทั้งหมดในเครื่อง และเริ่มใหม่?'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('ลบ')));
    await tester.pumpAndSettle();
    expect(s.data.patient, '');
    await disposeApp(tester);
  });
}
