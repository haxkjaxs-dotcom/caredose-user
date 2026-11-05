import 'dart:async';

import 'package:caredose/screens/login_screen.dart';
import 'package:caredose/screens/otp_screen.dart';
import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/state/auth_state.dart';
import 'package:caredose/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth_repository.dart';

Future<(AuthState, FakeAuthRepository)> pumpScreen(WidgetTester tester, Widget screen) async {
  SharedPreferences.setMockInitialValues({});
  final repo = FakeAuthRepository();
  final auth = AuthState(repo, await SharedPreferences.getInstance());
  await auth.init();
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: auth,
    child: MaterialApp(theme: buildTheme(), home: Scaffold(body: SingleChildScrollView(child: screen))),
  ));
  return (auth, repo);
}

Future<void> unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  group('LoginScreen', () {
    testWidgets('rejects a bad number without calling the backend', (tester) async {
      final (_, repo) = await pumpScreen(tester, LoginScreen(onCodeSent: (_) {}));
      await tester.enterText(find.byKey(const ValueKey('phone')), '12345');
      await tester.tap(find.text('ส่งรหัส OTP'));
      await tester.pump();
      expect(find.text('กรุณากรอกเบอร์มือถือ 10 หลักให้ถูกต้อง'), findsOneWidget);
      expect(repo.sendCalls, 0);
      await unmount(tester);
    });

    testWidgets('sends the OTP to the normalized number', (tester) async {
      String? sent;
      final (_, repo) = await pumpScreen(tester, LoginScreen(onCodeSent: (p) => sent = p));
      await tester.enterText(find.byKey(const ValueKey('phone')), '081-234-5678');
      await tester.tap(find.text('ส่งรหัส OTP'));
      await tester.pumpAndSettle();
      expect(repo.sendCalls, 1);
      expect(sent, '+66812345678');
      await unmount(tester);
    });

    testWidgets('shows the failure message from the backend', (tester) async {
      final (_, repo) = await pumpScreen(tester, LoginScreen(onCodeSent: (_) {}));
      repo.failure = const AuthFailure(AuthFailureKind.rateLimited);
      await tester.enterText(find.byKey(const ValueKey('phone')), '0812345678');
      await tester.tap(find.text('ส่งรหัส OTP'));
      await tester.pumpAndSettle();
      expect(find.text('ขอรหัสบ่อยเกินไป กรุณารอสักครู่'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a double tap sends only one request', (tester) async {
      final (_, repo) = await pumpScreen(tester, LoginScreen(onCodeSent: (_) {}));
      final gate = Completer<void>();
      repo.gate = gate;
      await tester.enterText(find.byKey(const ValueKey('phone')), '0812345678');
      await tester.tap(find.text('ส่งรหัส OTP'));
      await tester.pump();
      await tester.tap(find.text('ส่งรหัส OTP'), warnIfMissed: false);
      await tester.pump();
      expect(repo.sendCalls, 1);
      gate.complete();
      await tester.pumpAndSettle();
      await unmount(tester);
    });
  });

  group('OtpScreen', () {
    Widget otp({VoidCallback? onChange}) => OtpScreen(phoneE164: '+66812345678', onChangePhone: onChange ?? () {});

    testWidgets('shows which number the code was sent to', (tester) async {
      await pumpScreen(tester, otp());
      expect(find.text('ส่งรหัส OTP ไปยัง 0812345678 แล้ว'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('requires 6 digits', (tester) async {
      final (_, repo) = await pumpScreen(tester, otp());
      await tester.enterText(find.byKey(const ValueKey('otp')), '12');
      await tester.tap(find.text('ยืนยัน'));
      await tester.pump();
      expect(find.text('กรุณากรอกรหัส OTP 6 หลัก'), findsOneWidget);
      expect(repo.verifyCalls, 0);
      await unmount(tester);
    });

    testWidgets('a wrong code shows the backend message', (tester) async {
      final (_, repo) = await pumpScreen(tester, otp());
      repo.failure = const AuthFailure(AuthFailureKind.invalidCode);
      await tester.enterText(find.byKey(const ValueKey('otp')), '123456');
      await tester.tap(find.text('ยืนยัน'));
      await tester.pumpAndSettle();
      expect(find.text('รหัส OTP ไม่ถูกต้องหรือหมดอายุ'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('resend is locked for 60 seconds then sends again', (tester) async {
      final (_, repo) = await pumpScreen(tester, otp());
      expect(find.text('ส่งรหัสอีกครั้งใน 60 วินาที'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'ส่งรหัสอีกครั้งใน 60 วินาที')).onPressed, isNull);
      await tester.pump(const Duration(seconds: 60));
      final resend = find.widgetWithText(OutlinedButton, 'ส่งรหัสอีกครั้ง');
      expect(tester.widget<OutlinedButton>(resend).onPressed, isNotNull);
      await tester.tap(resend);
      await tester.pumpAndSettle();
      expect(repo.sendCalls, 1);
      await unmount(tester);
    });

    testWidgets('a double tap on confirm verifies once', (tester) async {
      final (_, repo) = await pumpScreen(tester, otp());
      final gate = Completer<void>();
      repo.gate = gate;
      await tester.enterText(find.byKey(const ValueKey('otp')), '123456');
      await tester.tap(find.text('ยืนยัน'));
      await tester.pump();
      await tester.tap(find.text('ยืนยัน'), warnIfMissed: false);
      await tester.pump();
      expect(repo.verifyCalls, 1);
      gate.complete();
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets('change number calls back', (tester) async {
      var changed = false;
      await pumpScreen(tester, otp(onChange: () => changed = true));
      await tester.tap(find.text('เปลี่ยนเบอร์'));
      expect(changed, true);
      await unmount(tester);
    });
  });
}
