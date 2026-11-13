import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'relative_repository.dart';
import 'supabase_auth_repository.dart' show guardCall;

// Thin network wrapper, no unit tests: the logic lives in RelativeSync and Relative.fromServer.
class SupabaseRelativeRepository implements RelativeRepository {
  SupabaseRelativeRepository(this._c);
  final SupabaseClient _c;

  @override
  Future<List<Relative>> fetch() => guardCall(() async {
        final rows = await _c.rpc('list_my_relatives') as List;
        return [for (final r in rows) Relative.fromServer(Json.from(r as Map))];
      });

  @override
  Future<String> save({String? id, required String name, required String rel, required String phone}) => guardCall(() async {
        final rid = await _c.rpc('save_my_relative', params: {'p_id': id, 'p_name': name, 'p_relationship': rel, 'p_phone': phone});
        return rid as String;
      });

  @override
  Future<void> delete(String id) => guardCall(() async {
        await _c.rpc('delete_my_relative', params: {'p_id': id});
      });
}
