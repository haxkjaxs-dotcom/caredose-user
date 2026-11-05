import 'package:caredose/auth_gate.dart';
import 'package:caredose/models/profile.dart';
import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/state/auth_state.dart';
import 'package:caredose/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth_repository.dart';
import 'helpers.dart' show tapVisible;

class Harness {
  Harness(this.repo, this.auth, this.signedInEvents);
  final FakeAuthRepository repo;
  final AuthState auth;
  final List<Profile> signedInEvents;
}

Future<Harness> pumpGate(WidgetTester tester, FakeAuthRepository repo, {bool init = true}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final events = <Profile>[];
  final auth = AuthState(repo, await SharedPreferences.getInstance(), onSignedIn: (p, _) => events.add(p));
  if (init) await auth.init();
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: auth,
    child: MaterialApp(theme: buildTheme(), home: const AuthGate(child: Text('HOME'))),
  ));
  await tester.pump();
  return Harness(repo, auth, events);
}

Future<void> unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  testWidgets('loading shows a spinner', (tester) async {
    await pumpGate(tester, FakeAuthRepository(), init: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('logged out: phone, then OTP, and change number goes back', (tester) async {
    await pumpGate(tester, FakeAuthRepository());
    expect(find.text('ส่งรหัส OTP'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('phone')), '0812345678');
    await tester.tap(find.text('ส่งรหัส OTP'));
    await tester.pumpAndSettle();
    expect(find.text('ส่งรหัส OTP ไปยัง 0812345678 แล้ว'), findsOneWidget);
    await tester.tap(find.text('เปลี่ยนเบอร์'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('phone')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('signed in without a profile shows the profile form', (tester) async {
    await pumpGate(tester, FakeAuthRepository(signedIn: true));
    expect(find.text('ยินยอมให้เก็บข้อมูลสุขภาพของฉันไว้ในระบบ'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('ready shows the app', (tester) async {
    await pumpGate(tester, FakeAuthRepository(signedIn: true, stored: sampleProfile));
    expect(find.text('HOME'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('unavailable offers a retry that recovers', (tester) async {
    final repo = FakeAuthRepository(signedIn: true, stored: sampleProfile)..failure = const AuthFailure(AuthFailureKind.network);
    await pumpGate(tester, repo);
    expect(find.text('เชื่อมต่อไม่ได้ กรุณาลองใหม่'), findsOneWidget);
    repo.failure = null;
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('full first-time flow: phone -> OTP -> profile -> app', (tester) async {
    final h = await pumpGate(tester, FakeAuthRepository());
    await tester.enterText(find.byKey(const ValueKey('phone')), '081-234-5678');
    await tester.tap(find.text('ส่งรหัส OTP'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('otp')), '123456');
    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();
    expect(find.text('ยินยอมให้เก็บข้อมูลสุขภาพของฉันไว้ในระบบ'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('nickname')), 'สมศรี');
    await tester.enterText(find.byKey(const ValueKey('full-name')), 'สมศรี ใจดี');
    await tester.enterText(find.byKey(const ValueKey('age')), '65');
    await tapVisible(tester, find.widgetWithText(FilterChip, 'ไม่มีโรคประจำตัว'));
    await tapVisible(tester, find.text('ยินยอมให้เก็บข้อมูลสุขภาพของฉันไว้ในระบบ'));
    await tapVisible(tester, find.widgetWithText(FilledButton, 'บันทึก'));
    expect(find.text('HOME'), findsOneWidget);
    expect(h.signedInEvents.single.nickname, 'สมศรี');
    expect(h.repo.lastSaved?.conditions, ['ไม่มีโรคประจำตัว']);
    await unmount(tester);
  });
}
