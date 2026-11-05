import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('shows header and switches through all four tabs', (tester) async {
    await pumpApp(tester);
    expect(find.text('CareDose'), findsOneWidget);
    expect(find.text('ยาอุ่นใจ'), findsOneWidget);
    for (final label in ['ประวัติ', 'ญาติ/นัด', 'BMI', 'หน้าหลัก']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    await disposeApp(tester);
  });
}
