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

final testNow = DateTime(2026, 11, 4, 9);

Future<AppState> makeState({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  return AppState(Storage(await SharedPreferences.getInstance()), FakeScheduler(), clock: () => testNow);
}

/// Pumps the whole app on a 360x800 phone-sized screen.
Future<AppState> pumpApp(WidgetTester tester, {AppState? state}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final s = state ?? await makeState();
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const CareDoseApp()));
  await tester.pumpAndSettle();
  return s;
}

/// Unmounts the app so periodic timers are cancelled before the test ends.
Future<void> disposeApp(WidgetTester tester) => tester.pumpWidget(const SizedBox());
