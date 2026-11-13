import 'dart:convert';

import 'package:caredose/models/models.dart';
import 'package:caredose/services/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<void> openContacts(WidgetTester tester) async {
  await tester.tap(find.text('ญาติ/นัด').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows patient summary, seeded relative and appointment', (tester) async {
    await pumpApp(tester);
    await openContacts(tester);
    expect(find.text('คุณแม่สมศรี'), findsOneWidget);
    expect(find.text('วันนี้ ทานแล้ว 0 จาก 5 รายการ'), findsOneWidget);
    expect(find.text('สมชาย'), findsOneWidget);
    expect(find.text('นัดหมายแพทย์'), findsOneWidget);
    expect(find.textContaining('โรงพยาบาลศิริราช', findRichText: true), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('adding a relative requires name and phone, then saves', (tester) async {
    final s = await pumpApp(tester);
    await openContacts(tester);
    await tapVisible(tester, find.text('+ เพิ่มญาติ'));
    await tapVisible(tester, find.widgetWithText(FilledButton, 'บันทึก'));
    expect(find.text('กรุณากรอกชื่อและเบอร์โทร'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'สมหญิง');
    await tester.enterText(fields.at(1), 'ลูกสาว');
    await tester.enterText(fields.at(2), '0899999999');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'บันทึก'));
    expect(s.data.relatives.map((r) => r.name), ['สมชาย', 'สมหญิง']);
    expect(find.text('สมหญิง'), findsOneWidget);
    expect(lastRelativeRepo.saved.single, (id: null, name: 'สมหญิง', rel: 'ลูกสาว', phone: '0899999999'));
    await disposeApp(tester);
  });

  testWidgets('deleting a relative asks for confirmation', (tester) async {
    final s = await pumpApp(tester);
    await openContacts(tester);
    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'แก้ไข'));
    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'ลบ'));
    expect(find.text('ต้องการลบ "สมชาย" ใช่หรือไม่?'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('ลบ')));
    await tester.pumpAndSettle();
    expect(s.data.relatives, isEmpty);
    expect(lastRelativeRepo.deleted, ['r1']);
    await disposeApp(tester);
  });

  testWidgets('a server failure keeps the form open with the message and leaves the list alone', (tester) async {
    final s = await pumpApp(tester);
    await openContacts(tester);
    lastRelativeRepo.failure = const AuthFailure(AuthFailureKind.network);
    await tapVisible(tester, find.text('+ เพิ่มญาติ'));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'สมหญิง');
    await tester.enterText(fields.at(2), '0899999999');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'บันทึก'));
    expect(find.text('ไม่มีอินเทอร์เน็ต กรุณาลองใหม่'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'บันทึก'), findsOneWidget);
    expect(s.data.relatives.map((r) => r.name), ['สมชาย']);
    await disposeApp(tester);
  });

  testWidgets('too long name, relationship or phone is refused before the server is called', (tester) async {
    await pumpApp(tester);
    await openContacts(tester);
    await tapVisible(tester, find.text('+ เพิ่มญาติ'));
    final fields = find.byType(TextField);
    Future<void> tryWith(String name, String rel, String phone, String message) async {
      await tester.enterText(fields.at(0), name);
      await tester.enterText(fields.at(1), rel);
      await tester.enterText(fields.at(2), phone);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'บันทึก'));
      expect(find.text(message), findsOneWidget);
    }
    await tryWith('ก' * 101, '', '1', 'ชื่อต้องไม่เกิน 100 ตัวอักษร');
    await tryWith('ก', 'ข' * 51, '1', 'ความสัมพันธ์ต้องไม่เกิน 50 ตัวอักษร');
    await tryWith('ก', '', '1' * 21, 'เบอร์โทรต้องไม่เกิน 20 ตัว');
    expect(lastRelativeRepo.saveCalls, 0);
    await disposeApp(tester);
  });

  testWidgets('the 21st relative is refused with the reason, without calling the server', (tester) async {
    final s = await pumpApp(tester);
    s.applyRelatives([for (var i = 1; i <= 20; i++) Relative(id: 'u$i', name: 'ญาติ $i', phone: '08$i')]);
    await openContacts(tester);
    await tapVisible(tester, find.text('+ เพิ่มญาติ'));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'คนที่ 21');
    await tester.enterText(fields.at(2), '0899999999');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'บันทึก'));
    expect(find.text('เพิ่มญาติได้ไม่เกิน 20 คน'), findsOneWidget);
    expect(lastRelativeRepo.saveCalls, 0);
    await disposeApp(tester);
  });

  testWidgets('a relative an Admin added can be called but not edited', (tester) async {
    final s = await pumpApp(tester);
    s.applyRelatives(const [Relative(id: 'u9', name: 'พี่หมอ', rel: 'พี่', phone: '0811111111', editable: false)]);
    await openContacts(tester);
    expect(find.text('พี่หมอ'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'โทรหาญาติ'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'แก้ไข'), findsNothing);
    await disposeApp(tester);
  });

  testWidgets('rescheduled appointment shows the previous time', (tester) async {
    final d = AppData.seed(testNow).copyWith(appts: const [
      Appt(
        id: 'a1',
        at: '2026-11-12T10:00',
        place: 'รพ.',
        dept: '',
        note: '',
        status: 'rescheduled',
        previousAt: '2026-11-09T09:30',
      ),
    ]);
    final s = await makeState(prefs: {'caredose': jsonEncode(d.toJson())});
    await pumpApp(tester, state: s);
    await openContacts(tester);
    expect(find.text('เลื่อนนัด'), findsOneWidget);
    expect(find.text('กำหนดเดิม'), findsOneWidget);
    expect(find.textContaining('ไม่ระบุ', findRichText: true), findsOneWidget);
    await disposeApp(tester);
  });
}
