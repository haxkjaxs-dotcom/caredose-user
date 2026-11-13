import 'dart:convert';

import 'package:caredose/app.dart';
import 'package:caredose/logic/auth_validators.dart';
import 'package:caredose/logic/thai_date.dart';
import 'package:caredose/models/models.dart';
import 'package:caredose/services/log_outbox.dart';
import 'package:caredose/services/notice_repository.dart';
import 'package:caredose/services/notice_sync.dart';
import 'package:caredose/services/relative_sync.dart';
import 'package:caredose/services/storage.dart';
import 'package:caredose/state/app_state.dart';
import 'package:caredose/state/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth_repository.dart';
import 'fake_med_repository.dart';
import 'fake_notice_repository.dart';
import 'fake_relative_repository.dart';

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

/// The sample data production `AppData.seed` used to contain (3 meds, doctor, relative, appointment).
AppData sampleData(DateTime now) {
  final today = dateKey(now);
  return AppData(
    patient: 'คุณแม่สมศรี',
    size: 'normal',
    notify: true,
    notifyChannel: 'app',
    repeatReminder: true,
    verifiedPhone: '081-234-5678',
    meds: [
      Med(id: 'm1', name: 'ยาลดความดัน', dosage: '1 เม็ด', meal: 'หลังอาหาร', times: const ['08:00'], start: today, note: 'ทานพร้อมน้ำเปล่า', color: medColors[0]),
      Med(id: 'm2', name: 'ยาเบาหวาน', dosage: '1 เม็ด', meal: 'ก่อนอาหาร', times: const ['08:00', '18:00'], start: today, color: medColors[1]),
      Med(id: 'm3', name: 'แคลเซียม', dosage: '2 เม็ด', meal: 'หลังอาหาร', times: const ['12:30', '21:00'], start: today, color: medColors[2]),
    ],
    doctors: const [Doctor(id: 'd1', name: 'นพ.วิชัย ใจดี', spec: 'อายุรกรรม / โรคความดัน', phone: '021234567')],
    relatives: const [Relative(id: 'r1', name: 'สมชาย', rel: 'ลูกชาย', phone: '0812345678')],
    appts: [
      Appt(
        id: 'a1',
        at: '${dateKey(now.add(const Duration(days: 5)))}T09:30',
        place: 'โรงพยาบาลศิริราช',
        dept: 'อายุรกรรม',
        note: 'งดน้ำและอาหารก่อนตรวจ 8 ชั่วโมง',
        status: 'confirmed',
      ),
    ],
  );
}

/// Scheduler of the most recent [makeState] call, for asserting reschedules.
late FakeScheduler lastScheduler;

Future<AppState> makeState({Map<String, Object> prefs = const {}}) async {
  // Starts from the sample data unless the test supplies its own saved data.
  SharedPreferences.setMockInitialValues({'caredose': jsonEncode(sampleData(testNow).toJson()), ...prefs});
  lastScheduler = FakeScheduler();
  return AppState(Storage(await SharedPreferences.getInstance()), lastScheduler, clock: () => testNow);
}

/// Auth objects of the most recent [pumpApp] call (signed in with a profile unless overridden).
late AuthState lastAuth;
late FakeAuthRepository lastAuthRepo;
late LogOutbox lastOutbox;
late FakeMedRepository lastMedRepo;
late FakeNoticeRepository lastNoticeRepo;
late NoticeSync lastNoticeSync;
late FakeRelativeRepository lastRelativeRepo;

class _NoDisplay implements NoticeDisplay {
  @override
  Future<bool> show(int id, String title, String body) async => true;
}

/// Pumps the whole app on a 360x800 phone-sized screen. By default the user is already
/// signed in with a profile, so tests land on the main app; pass [signedIn]=false for the login flow.
Future<AppState> pumpApp(WidgetTester tester, {AppState? state, FakePermissions? permissions, bool signedIn = true}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final s = state ?? await makeState();
  lastAuthRepo = FakeAuthRepository(signedIn: signedIn, stored: signedIn ? sampleProfile : null);
  final prefs = await SharedPreferences.getInstance();
  lastMedRepo = FakeMedRepository();
  lastOutbox = LogOutbox(prefs, lastMedRepo);
  lastNoticeRepo = FakeNoticeRepository();
  lastNoticeSync = NoticeSync(lastNoticeRepo, _NoDisplay(), prefs);
  lastRelativeRepo = FakeRelativeRepository();
  // Same wiring as main(): a fresh sign-in fills the local name/phone; sign out flushes, then wipes local data.
  lastAuth = AuthState(
    lastAuthRepo,
    prefs,
    onSignedIn: (p, phone) {
      s.setPatient(p.nickname);
      s.setVerifiedPhone(displayPhone(phone));
    },
    beforeSignOut: lastOutbox.flush,
    onSignedOut: () async {
      await lastOutbox.clear();
      await lastNoticeSync.clearShown();
      await s.resetAll();
    },
  );
  await lastAuth.init();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: s),
      ChangeNotifierProvider<AuthState>.value(value: lastAuth),
      Provider<NotificationPermissions>.value(value: permissions ?? FakePermissions()),
      Provider<LogOutbox>.value(value: lastOutbox),
      Provider<NoticeSync>.value(value: lastNoticeSync),
      Provider<RelativeSync>.value(value: RelativeSync(lastRelativeRepo, s)),
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
