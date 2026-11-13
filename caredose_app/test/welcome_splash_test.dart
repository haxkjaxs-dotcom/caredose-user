import 'package:caredose/screens/welcome_splash.dart';
import 'package:caredose/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app() => MaterialApp(theme: buildTheme(), home: const WelcomeSplash(child: Text('HOME')));

void main() {
  testWidgets('types the welcome text letter by letter, then shows the app', (tester) async {
    await tester.pumpWidget(app());
    expect(find.text('HOME'), findsNothing);
    expect(find.text('ยินดีต้อนรับ'), findsNothing); // nothing typed yet

    await tester.pump(const Duration(milliseconds: 500));
    final partial = tester.widget<Text>(find.byKey(const ValueKey('welcome-text'))).data!;
    expect('ยินดีต้อนรับ'.startsWith(partial), true);
    expect(partial.isNotEmpty && partial.length < 'ยินดีต้อนรับ'.length, true);

    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('ยินดีต้อนรับ'), findsOneWidget); // fully typed, still holding
    expect(find.text('HOME'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(find.byKey(const ValueKey('welcome-text')), findsNothing);
  });

  testWidgets('tapping skips the wait', (tester) async {
    await tester.pumpWidget(app());
    await tester.tapAt(tester.getCenter(find.byType(Scaffold)));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('leaving early leaves no timer behind', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox());
  });
}
