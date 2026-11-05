import 'package:caredose/logic/thai_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<void> openHistory(WidgetTester tester) async {
  await tester.tap(find.text('ประวัติ').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows today summary counts and the day list', (tester) async {
    await pumpApp(tester);
    await openHistory(tester);
    expect(find.text('ยาลดความดัน'), findsOneWidget);
    expect(find.text('เลือกแล้ว: ${thDate('2026-11-04')}'), findsWidgets);
    await disposeApp(tester);
  });

  testWidgets('picking another day in the calendar changes the selection', (tester) async {
    await pumpApp(tester);
    await openHistory(tester);
    final cell = find.byKey(const ValueKey('hist-day-2026-11-05'));
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(find.text('เลือกแล้ว: ${thDate('2026-11-05')}'), findsWidgets);
    await disposeApp(tester);
  });

  testWidgets('export button is disabled when the range is reversed', (tester) async {
    await pumpApp(tester);
    await openHistory(tester);
    final cell = find.byKey(const ValueKey('range-day-2026-11-10'));
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell); // sets "from" to the 10th while "to" stays on the 4th
    await tester.pumpAndSettle();
    final export = find.widgetWithText(FilledButton, 'Export Excel');
    await tester.ensureVisible(export);
    expect(tester.widget<FilledButton>(export).onPressed, isNull);
    expect(find.text('วันที่สิ้นสุดต้องไม่ก่อนวันที่เริ่ม'), findsOneWidget);
    await disposeApp(tester);
  });
}
