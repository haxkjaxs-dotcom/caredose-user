import '../models/models.dart';

/// The patient's relatives on the server. Methods throw only `AuthFailure`.
abstract class RelativeRepository {
  /// Every live relative of the signed-in patient, the ones an Admin linked included.
  Future<List<Relative>> fetch();

  /// Creates ([id] null) or changes a relative; returns its server id.
  Future<String> save({String? id, required String name, required String rel, required String phone});

  Future<void> delete(String id);
}
