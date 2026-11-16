import 'dart:async';

import 'package:caredose/models/profile.dart';
import 'package:caredose/screens/profile_screen.dart';
import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/state/auth_state.dart';
import 'package:caredose/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth_repository.dart';

Future<FakeAuthRepository> pumpProfile(WidgetTester tester, {ProfileDraft? draft, AuthFailure? draftFailure}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final repo = FakeAuthRepository(signedIn: true)
    ..draft = draft
    ..draftFailure = draftFailure;
  final auth = AuthState(repo, await SharedPreferences.getInstance());
  await auth.init();
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: auth,
    child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: SingleChildScrollView(child: ProfileScreen()))),
  ));
  await tester.pumpAndSettle(); // the pre-fill arrives asynchronously
  return repo;
}

Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> pickTitle(WidgetTester tester, String t) async {
  await tapVisible(tester, find.byKey(const ValueKey('title')));
  await tester.tap(find.text(t).last);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, {String nick = 'สมศรี', String name = 'สมศรี ใจดี', String age = '65', String? title = 'นาง'}) async {
  if (title != null) await pickTitle(tester, title);
  await tester.enterText(find.byKey(const ValueKey('nickname')), nick);
  await tester.enterText(find.byKey(const ValueKey('full-name')), name);
  await tester.enterText(find.byKey(const ValueKey('age')), age);
}

Finder chip(String label) => find.widgetWithText(FilterChip, label);
Finder saveButton() => find.widgetWithText(FilledButton, 'บันทึก');
Finder consent() => find.text('ยินยอมให้เก็บข้อมูลสุขภาพของฉันไว้ในระบบ');
Future<void> unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  testWidgets('save is disabled until consent is ticked', (tester) async {
    await pumpProfile(tester);
    await tester.ensureVisible(saveButton());
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    await tapVisible(tester, consent());
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNotNull);
    await unmount(tester);
  });

  testWidgets('saves the entered profile', (tester) async {
    final repo = await pumpProfile(tester);
    await fill(tester);
    await tapVisible(tester, chip('เบาหวาน'));
    await tester.enterText(find.byKey(const ValueKey('other-conditions')), 'ภูมิแพ้');
    await tapVisible(tester, consent());
    await tapVisible(tester, saveButton());
    expect(repo.saveCalls, 1);
    expect(repo.lastSaved?.nickname, 'สมศรี');
    expect(repo.lastSaved?.fullName, 'นาง สมศรี ใจดี');
    expect(repo.lastSaved?.age, 65);
    expect(repo.lastSaved?.conditions, ['เบาหวาน', 'ภูมิแพ้']);
    await unmount(tester);
  });

  testWidgets('a title is required and is not added twice', (tester) async {
    final repo = await pumpProfile(tester);
    await fill(tester, title: null);
    await tapVisible(tester, chip('เบาหวาน'));
    await tapVisible(tester, consent());
    await tapVisible(tester, saveButton());
    expect(find.text('กรุณาเลือกคำนำหน้า'), findsOneWidget);
    expect(repo.saveCalls, 0);

    tester.view.physicalSize = const Size(360, 1800); // tall enough that the save button stays on screen below the error box
    await tester.pumpAndSettle();
    await pickTitle(tester, 'นาย');
    await tester.enterText(find.byKey(const ValueKey('full-name')), 'นาย ธนพล ใจดี');
    await tapVisible(tester, saveButton());
    expect(repo.lastSaved?.fullName, 'นาย ธนพล ใจดี');
    await unmount(tester);
  });

  testWidgets('invalid age and missing conditions are reported without saving', (tester) async {
    final repo = await pumpProfile(tester);
    await fill(tester, age: '0');
    await tapVisible(tester, chip('เบาหวาน'));
    await tapVisible(tester, consent());
    await tapVisible(tester, saveButton());
    expect(find.text('กรุณากรอกอายุ 1–120 ปี'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('age')), '30');
    await tapVisible(tester, chip('เบาหวาน')); // deselect -> no conditions
    await tapVisible(tester, saveButton());
    expect(find.text('กรุณาเลือกโรคประจำตัวหรือเลือกไม่มี'), findsOneWidget);
    expect(repo.saveCalls, 0);
    await unmount(tester);
  });

  testWidgets('"no conditions" and other conditions exclude each other', (tester) async {
    await pumpProfile(tester);
    bool selected(String l) => tester.widget<FilterChip>(chip(l)).selected;
    await tapVisible(tester, chip('เบาหวาน'));
    await tester.enterText(find.byKey(const ValueKey('other-conditions')), 'ภูมิแพ้');
    await tapVisible(tester, chip('ไม่มีโรคประจำตัว'));
    expect(selected('เบาหวาน'), false);
    expect(selected('ไม่มีโรคประจำตัว'), true);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('other-conditions'))).controller!.text, isEmpty);

    await tapVisible(tester, chip('โรคไต'));
    expect(selected('ไม่มีโรคประจำตัว'), false);
    expect(selected('โรคไต'), true);

    await tapVisible(tester, chip('ไม่มีโรคประจำตัว'));
    await tester.enterText(find.byKey(const ValueKey('other-conditions')), 'x');
    await tester.pump();
    expect(selected('ไม่มีโรคประจำตัว'), false);
    await unmount(tester);
  });

  testWidgets('a failed save shows the error and keeps everything typed', (tester) async {
    final repo = await pumpProfile(tester);
    repo.failure = const AuthFailure(AuthFailureKind.network);
    await fill(tester);
    await tapVisible(tester, chip('เบาหวาน'));
    await tapVisible(tester, consent());
    await tapVisible(tester, saveButton());
    expect(find.text('ไม่มีอินเทอร์เน็ต กรุณาลองใหม่'), findsOneWidget);
    expect(find.text('สมศรี'), findsOneWidget);
    expect(find.text('สมศรี ใจดี'), findsOneWidget);
    expect(find.text('65'), findsOneWidget);
    expect(tester.widget<FilterChip>(chip('เบาหวาน')).selected, true);
    // and the user can retry once the network is back
    repo.failure = null;
    await tapVisible(tester, saveButton());
    expect(repo.saveCalls, 2);
    await unmount(tester);
  });

  testWidgets('largest text size does not overflow the form', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final auth = AuthState(FakeAuthRepository(signedIn: true), await SharedPreferences.getInstance());
    await auth.init();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: auth,
      child: MaterialApp(
        theme: buildTheme(),
        builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.5)), child: child!),
        home: const Scaffold(body: SingleChildScrollView(child: ProfileScreen())),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('a double tap on save sends one request', (tester) async {
    final repo = await pumpProfile(tester);
    final gate = Completer<void>();
    repo.gate = gate;
    await fill(tester);
    await tapVisible(tester, chip('เบาหวาน'));
    await tapVisible(tester, consent());
    await tester.ensureVisible(saveButton());
    await tester.tap(saveButton());
    await tester.pump();
    await tester.tap(saveButton(), warnIfMissed: false);
    await tester.pump();
    expect(repo.saveCalls, 1);
    gate.complete();
    await tester.pumpAndSettle();
    await unmount(tester);
  });

  testWidgets('the form is pre-filled from what the admin typed, except the nickname', (tester) async {
    final repo = await pumpProfile(tester,
        draft: const ProfileDraft(fullName: 'นางสาว สมหญิง ใจดี', age: 41, conditions: ['เบาหวาน', 'ภูมิแพ้']));
    String text(String key) => tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
    expect(text('nickname'), isEmpty);
    expect(text('full-name'), 'สมหญิง ใจดี');
    expect(text('age'), '41');
    expect(text('other-conditions'), 'ภูมิแพ้');
    expect(tester.widget<FilterChip>(chip('เบาหวาน')).selected, true);
    expect(find.text('นางสาว'), findsOneWidget); // shown in the title field

    tester.view.physicalSize = const Size(360, 1800); // tall enough that every control stays on screen
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('nickname')), 'หญิง');
    await tapVisible(tester, consent());
    await tapVisible(tester, saveButton());
    expect(repo.lastSaved?.fullName, 'นางสาว สมหญิง ใจดี');
    expect(repo.lastSaved?.age, 41);
    expect(repo.lastSaved?.conditions, ['เบาหวาน', 'ภูมิแพ้']);
    await unmount(tester);
  });

  testWidgets('a name without a known title is filled whole and the title stays to be picked; "no conditions" is kept', (tester) async {
    await pumpProfile(tester, draft: const ProfileDraft(fullName: 'สมชาย ใจดี', conditions: ['ไม่มีโรคประจำตัว']));
    expect(tester.widget<TextField>(find.byKey(const ValueKey('full-name'))).controller!.text, 'สมชาย ใจดี');
    expect(find.text('เลือกคำนำหน้า'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('age'))).controller!.text, isEmpty);
    expect(tester.widget<FilterChip>(chip('ไม่มีโรคประจำตัว')).selected, true);
    await unmount(tester);
  });

  testWidgets('a failed pre-fill leaves an empty, usable form', (tester) async {
    await pumpProfile(tester, draftFailure: const AuthFailure(AuthFailureKind.network));
    expect(tester.widget<TextField>(find.byKey(const ValueKey('full-name'))).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}
