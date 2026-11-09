import 'package:caredose/screens/not_registered_screen.dart';
import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/state/auth_state.dart';
import 'package:caredose/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth_repository.dart';

Future<(AuthState, FakeAuthRepository)> pumpScreen(WidgetTester tester, FakeAuthRepository repo) async {
  SharedPreferences.setMockInitialValues({});
  final auth = AuthState(repo, await SharedPreferences.getInstance());
  await auth.init();
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: auth,
    child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: SingleChildScrollView(child: NotRegisteredScreen()))),
  ));
  return (auth, repo);
}

void main() {
  testWidgets('shows the message; retry asks the backend again', (tester) async {
    final (auth, repo) = await pumpScreen(tester, FakeAuthRepository(signedIn: true)..claimResult = null);
    expect(find.text('ยังไม่พบเบอร์นี้ในระบบ กรุณาติดต่อผู้ดูแล'), findsOneWidget);
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(repo.claimCalls, 2);
    expect(auth.status, AuthStatus.notRegistered);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sign out button signs out', (tester) async {
    final (auth, repo) = await pumpScreen(tester, FakeAuthRepository(signedIn: true)..claimResult = null);
    await tester.tap(find.text('ออกจากระบบ'));
    await tester.pumpAndSettle();
    expect(repo.signOutCalls, 1);
    expect(auth.status, AuthStatus.loggedOut);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows the notice (duplicate phone) instead of the default text', (tester) async {
    await pumpScreen(tester, FakeAuthRepository(signedIn: true)..claimFailure = const AuthFailure(AuthFailureKind.duplicatePhone));
    expect(find.text('เบอร์นี้ซ้ำในระบบ กรุณาติดต่อผู้ดูแล'), findsOneWidget);
    expect(find.text('ยังไม่พบเบอร์นี้ในระบบ กรุณาติดต่อผู้ดูแล'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
