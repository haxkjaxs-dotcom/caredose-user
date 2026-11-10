import 'package:caredose/screens/notices_screen.dart';
import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/services/notice_repository.dart';
import 'package:caredose/services/notice_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_notice_repository.dart';

class _NoDisplay implements NoticeDisplay {
  @override
  Future<bool> show(int id, String title, String body) async => true;
}

Future<FakeNoticeRepository> pumpScreen(WidgetTester tester, {AuthFailure? failure}) async {
  SharedPreferences.setMockInitialValues({});
  final repo = FakeNoticeRepository()..failure = failure;
  final sync = NoticeSync(repo, _NoDisplay(), await SharedPreferences.getInstance());
  await tester.pumpWidget(MaterialApp(home: Provider<NoticeSync>.value(value: sync, child: const NoticesScreen())));
  return repo;
}

void main() {
  testWidgets('shows each message with its title and body, newest first', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = FakeNoticeRepository()
      ..recent = [
        notice('2', title: 'หัวข้อใหม่', body: 'ข้อความใหม่', at: DateTime(2026, 11, 10, 9, 30)),
        notice('1', title: 'หัวข้อเก่า', body: 'ข้อความเก่า', at: DateTime(2026, 11, 9, 8, 5)),
      ];
    final sync = NoticeSync(repo, _NoDisplay(), await SharedPreferences.getInstance());
    await tester.pumpWidget(MaterialApp(home: Provider<NoticeSync>.value(value: sync, child: const NoticesScreen())));
    await tester.pumpAndSettle();
    expect(find.text('หัวข้อใหม่'), findsOneWidget);
    expect(find.text('ข้อความเก่า'), findsOneWidget);
    expect(find.textContaining('09:30'), findsOneWidget);
    expect(tester.getTopLeft(find.text('หัวข้อใหม่')).dy, lessThan(tester.getTopLeft(find.text('หัวข้อเก่า')).dy));
  });

  testWidgets('shows the empty text when there are no messages', (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีข้อความจากผู้ดูแล'), findsOneWidget);
  });

  testWidgets('shows at most the 30 latest', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = FakeNoticeRepository()..recent = [for (var i = 0; i < 40; i++) notice('$i', title: 'ข้อความ$i')];
    final sync = NoticeSync(repo, _NoDisplay(), await SharedPreferences.getInstance());
    await tester.pumpWidget(MaterialApp(home: Provider<NoticeSync>.value(value: sync, child: const NoticesScreen())));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.text('ข้อความ29'), find.byType(ListView), const Offset(0, -300));
    expect(find.text('ข้อความ29'), findsOneWidget);
    expect(find.text('ข้อความ30'), findsNothing);
  });

  testWidgets('offline shows the empty text instead of an error', (tester) async {
    await pumpScreen(tester, failure: const AuthFailure(AuthFailureKind.network));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีข้อความจากผู้ดูแล'), findsOneWidget);
  });
}
