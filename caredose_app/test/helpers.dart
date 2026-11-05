import 'package:caredose/app.dart';
import 'package:caredose/logic/auth_validators.dart';
import 'package:caredose/models/models.dart';
import 'package:caredose/services/storage.dart';
import 'package:caredose/state/app_state.dart';
import 'package:caredose/state/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth_repository.dart';

class FakeScheduler implements NotificationScheduler {
  int calls = 0;
  @override
  Future<void> reschedule(AppData d, Set<String> dismissed, DateTime now) async => calls++;
}

class FakePermissions implements NotificationPermissions {
  FakePermissions({this.granted = true});
  bool granted;
  int requests = 0;
  @override
  Future<bool> permissionsGranted() async => granted;
  @override
  Future<bool> requestPermissions() async {
    requests++;
    granted = true;
    return true;
  }
}

final testNow = DateTime(2026, 11, 4, 9);

/// Scheduler of the most recent [makeState] call, for asserting reschedules.
late FakeScheduler lastScheduler;

Future<AppState> makeState({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  lastScheduler = FakeScheduler();
  return AppState(Storage(await SharedPreferences.getInstance()), lastScheduler, clock: () => testNow);
}

/// Auth objects of the most recent [pumpApp] call (signed in with a profile unless overridden).
late AuthState lastAuth;
late FakeAuthRepository lastAuthRepo;

/// Pumps the whole app on a 360x800 phone-sized screen. By default the user is already
/// signed in with a profile, so tests land on the main app; pass [signedIn]=false for the login flow.
Future<AppState> pumpApp(WidgetTester tester, {AppState? state, FakePermissions? permissions, bool signedIn = true}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final s = state ?? await makeState();
  lastAuthRepo = FakeAuthRepository(signedIn: signedIn, stored: signedIn ? sampleProfile : null);
  // Same wiring as main(): a fresh sign-in fills the local name/phone; sign out wipes local data.
  lastAuth = AuthState(
    lastAuthRepo,
    await SharedPreferences.getInstance(),
    onSignedIn: (p, phone) {
      s.setPatient(p.nickname);
      s.setVerifiedPhone(displayPhone(phone));
    },
    onSignedOut: () => s.resetAll(),
  );
  await lastAuth.init();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: s),
      ChangeNotifierProvider<AuthState>.value(value: lastAuth),
      Provider<NotificationPermissions>.value(value: permissions ?? FakePermissions()),
    ],
    child: const CareDoseApp(),
  ));
  await tester.pumpAndSettle();
  return s;
}

Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Unmounts the app so periodic timers are cancelled before the test ends.
Future<void> disposeApp(WidgetTester tester) => tester.pumpWidget(const SizedBox());
