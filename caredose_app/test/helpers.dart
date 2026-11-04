import 'package:caredose/app.dart';
import 'package:caredose/models/models.dart';
import 'package:caredose/services/storage.dart';
import 'package:caredose/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Pumps the whole app on a 360x800 phone-sized screen.
Future<AppState> pumpApp(WidgetTester tester, {AppState? state, FakePermissions? permissions}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final s = state ?? await makeState();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: s),
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
