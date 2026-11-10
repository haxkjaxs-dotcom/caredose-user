import 'models.dart' show Json;

/// A `notifications` row: a message an admin sent to this patient.
class Notice {
  final String id, title, body;
  final DateTime createdAt;
  final bool read;
  const Notice({required this.id, required this.title, required this.body, required this.createdAt, required this.read});

  /// Throws FormatException on a row without an id or a usable `created_at` (callers skip such rows).
  factory Notice.fromJson(Json j) {
    final id = j['id'];
    final created = j['created_at'];
    if (id is! String || id.isEmpty || created is! String) throw const FormatException('bad notification row');
    return Notice(
      id: id,
      title: j['title'] is String ? j['title'] as String : '',
      body: j['body'] is String ? j['body'] as String : '',
      createdAt: DateTime.parse(created),
      read: j['read'] == true,
    );
  }
}
