import '../models/notice.dart';

/// Admin messages on the server. Methods throw only `AuthFailure`.
abstract class NoticeRepository {
  /// Rows with `read = false`, oldest first.
  Future<List<Notice>> fetchUnread();

  /// Newest first.
  Future<List<Notice>> fetchRecent(int limit);

  Future<void> markRead(List<String> ids);

  /// Calls [onInsert] for every message inserted for the signed-in user from now on. Returns the cancel function.
  void Function() subscribe(void Function(Notice) onInsert);
}

/// Shows a message to the user outside the app (a system notification), so [NoticeSync] can be tested without the plugin.
abstract class NoticeDisplay {
  Future<void> show(int id, String title, String body);
}
