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
/// Returns false when it could not show it (plugin not ready yet): the message must then stay unread.
abstract class NoticeDisplay {
  Future<bool> show(int id, String title, String body);
}
