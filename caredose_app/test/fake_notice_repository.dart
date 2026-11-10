import 'dart:async';

import 'package:caredose/models/notice.dart';
import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/services/notice_repository.dart';

class FakeNoticeRepository implements NoticeRepository {
  List<Notice> unread = [];
  List<Notice> recent = [];
  AuthFailure? failure;
  Object? crash;
  AuthFailure? markFailure;
  final marked = <List<String>>[];
  void Function(Notice)? listener;
  int subscribes = 0, cancels = 0, fetchCalls = 0;

  /// When set, fetchUnread waits for it (to hold a pull open).
  Completer<void>? gate;

  @override
  Future<List<Notice>> fetchUnread() async {
    fetchCalls++;
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    if (crash != null) throw crash!;
    return List.of(unread);
  }

  @override
  Future<List<Notice>> fetchRecent(int limit) async {
    if (failure != null) throw failure!;
    return recent.take(limit).toList();
  }

  @override
  Future<void> markRead(List<String> ids) async {
    if (markFailure != null) throw markFailure!;
    marked.add(ids);
  }

  @override
  void Function() subscribe(void Function(Notice) onInsert) {
    subscribes++;
    listener = onInsert;
    return () {
      cancels++;
      listener = null;
    };
  }
}

Notice notice(String id, {String title = 't', String body = 'b', DateTime? at}) =>
    Notice(id: id, title: title, body: body, createdAt: at ?? DateTime.utc(2026, 11, 10, 3), read: false);
