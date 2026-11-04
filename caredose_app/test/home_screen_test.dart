import 'package:caredose/models/models.dart';
import 'package:caredose/widgets/med_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('lists the seeded medicines', (tester) async {
    await pumpApp(tester);
    expect(find.text('ยาลดความดัน'), findsWidgets);
    expect(find.text('ยาเบาหวาน'), findsWidgets);
    expect(find.text('แคลเซียม'), findsWidgets);
    expect(find.text('แพทย์ผู้ดูแล'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('tapping ทานแล้ว logs the dose and offers undo', (tester) async {
    final s = await pumpApp(tester);
    final button = find.widgetWithText(FilledButton, 'ทานแล้ว').first;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(s.data.logs.length, 1);
    expect(s.data.logs.keys.first, 'm1|2026-11-04|08:00');
    expect(find.text('ยกเลิกการบันทึก'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('add-medicine form rejects an empty name', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('+ เพิ่มยา'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'บันทึก');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('กรุณากรอกชื่อยา'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('extra-large text does not overflow the home screen', (tester) async {
    final state = await makeState();
    state.setSize('xl');
    await pumpApp(tester, state: state);
    expect(tester.takeException(), isNull);
    await disposeApp(tester);
  });

  test('validateMed messages', () {
    const ok = Med(id: '1', name: 'a', times: ['08:00'], start: '2026-11-04');
    expect(validateMed(ok), isNull);
    expect(validateMed(ok.copyWith(name: '  ')), 'กรุณากรอกชื่อยา');
    expect(validateMed(ok.copyWith(times: [])), 'กรุณาระบุเวลาเตือน');
    expect(validateMed(ok.copyWith(times: [''])), 'กรุณาระบุเวลาเตือน');
    expect(validateMed(ok.copyWith(end: '2026-11-03')), 'วันที่สิ้นสุดต้องไม่ก่อนวันที่เริ่ม');
    expect(validateMed(ok.copyWith(end: '2026-11-04')), isNull);
  });
}
