import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../models/notice.dart';
import 'notice_repository.dart';
import 'supabase_auth_repository.dart' show guardCall;

// Thin network wrapper, no unit tests (same convention as SupabaseMedRepository): the logic lives in NoticeSync.
// RLS (`notif_r`) already limits every query here to the signed-in user's own rows.
class SupabaseNoticeRepository implements NoticeRepository {
  SupabaseNoticeRepository(this._c);
  final SupabaseClient _c;

  List<Notice> _parse(List<dynamic> rows) {
    final out = <Notice>[];
    for (final r in rows) {
      try {
        out.add(Notice.fromJson(Json.from(r as Map)));
      } catch (e) {
        debugPrint('skipping a bad notification row: $e');
      }
    }
    return out;
  }

  @override
  Future<List<Notice>> fetchUnread() => guardCall(() async {
        final rows = await _c.from('notifications').select().eq('read', false).order('created_at');
        return _parse(rows);
      });

  @override
  Future<List<Notice>> fetchRecent(int limit) => guardCall(() async {
        final rows = await _c.from('notifications').select().order('created_at', ascending: false).limit(limit);
        return _parse(rows);
      });

  @override
  Future<void> markRead(List<String> ids) => guardCall(() async {
        if (ids.isEmpty) return;
        await _c.from('notifications').update({'read': true}).inFilter('id', ids);
      });

  @override
  void Function() subscribe(void Function(Notice) onInsert) {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return () {};
    final channel = _c
        .channel('notices-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (payload) {
            try {
              onInsert(Notice.fromJson(Json.from(payload.newRecord)));
            } catch (e) {
              debugPrint('bad realtime notification: $e');
            }
          },
        )
        .subscribe();
    return () => _c.removeChannel(channel);
  }
}
