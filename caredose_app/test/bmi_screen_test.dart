import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<void> openBmi(WidgetTester tester) async {
  await tester.tap(find.text('BMI'));
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String w, String h) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), w);
  await tester.enterText(fields.at(1), h);
}

void main() {
  testWidgets('calculates and shows BMI with category', (tester) async {
    final s = await pumpApp(tester);
    await openBmi(tester);
    await enter(tester, '58', '155');
    await tester.tap(find.text('คำนวณ BMI').last);
    await tester.pumpAndSettle();
    expect(s.data.bmis.length, 1);
    expect(find.text('24.1'), findsWidgets);
    expect(find.text('ปกติ'), findsWidgets);
    expect(find.text('ประวัติ BMI'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('empty weight shows validation error', (tester) async {
    final s = await pumpApp(tester);
    await openBmi(tester);
    await enter(tester, '', '155');
    await tester.tap(find.text('คำนวณ BMI').last);
    await tester.pumpAndSettle();
    expect(find.text('กรุณากรอกน้ำหนัก (กก.) และส่วนสูง (ซม.) ให้ถูกต้อง'), findsOneWidget);
    expect(s.data.bmis, isEmpty);
    await disposeApp(tester);
  });

  testWidgets('non-numeric input shows error and does not throw', (tester) async {
    final s = await pumpApp(tester);
    await openBmi(tester);
    await enter(tester, 'abc', '155');
    await tester.tap(find.text('คำนวณ BMI').last);
    await tester.pumpAndSettle();
    expect(find.text('กรุณากรอกน้ำหนัก (กก.) และส่วนสูง (ซม.) ให้ถูกต้อง'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(s.data.bmis, isEmpty);
    await disposeApp(tester);
  });
}
