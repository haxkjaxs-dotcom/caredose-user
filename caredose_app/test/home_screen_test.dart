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

  testWidgets('the ยังไม่ได้ทาน button logs skipped and the old ข้ามยา wording is gone', (tester) async {
    final s = await pumpApp(tester);
    expect(find.text('ข้ามยา'), findsNothing);
    final button = find.widgetWithText(OutlinedButton, 'ยังไม่ได้ทาน').first;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(s.data.logs.values.single.status, 'skipped');
    await disposeApp(tester);
  });

  testWidgets('patients cannot add medicines; the doctor does', (tester) async {
    await pumpApp(tester);
    expect(find.text('+ เพิ่มยา'), findsNothing);
    expect(find.textContaining('เพิ่มยา'), findsNothing);
    await disposeApp(tester);
  });

  testWidgets('extra-large text does not overflow the home screen', (tester) async {
    final state = await makeState();
    state.setSize('xl');
    await pumpApp(tester, state: state);
    expect(tester.takeException(), isNull);
    await disposeApp(tester);
  });
}
