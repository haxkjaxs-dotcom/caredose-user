import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../models/remote_plan.dart';
import 'auth_repository.dart';
import 'med_repository.dart';
import 'supabase_auth_repository.dart' show mapAuthError;

// Thin network wrapper, no unit tests: all mapping logic lives in remote_plan.dart.
class SupabaseMedRepository implements MedRepository {
  SupabaseMedRepository(this._c);
  final SupabaseClient _c;

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw mapAuthError(e);
    }
  }

  @override
  Future<List<RemotePlan>> fetchPlans() => _guard(() async {
        final rows = await _c
            .from('medication_plans')
            .select('*, medicines(generic_name,trade_name,warning), medication_schedules(id,time_of_day,days_of_week,interval_days)')
            .eq('status', 'active');
        return [for (final r in rows) RemotePlan.fromJson(Json.from(r))];
      });

  @override
  Future<List<RemoteLog>> fetchLogs(DateTime since) => _guard(() async {
        final rows = await _c
            .from('medication_logs')
            .select()
            .gte('scheduled_at', since.toUtc().toIso8601String())
            .order('scheduled_at');
        return [for (final r in rows) RemoteLog.fromJson(Json.from(r))];
      });

  @override
  Future<void> upsertLog(LogOp op) => _guard(() async {
        final uid = _c.auth.currentUser?.id;
        if (uid == null) throw const AuthFailure(AuthFailureKind.rejected);
        await _c.from('medication_logs').upsert({
          'plan_id': op.planId,
          'schedule_id': op.scheduleId,
          'scheduled_at': op.scheduledAt.toUtc().toIso8601String(),
          'status': op.status,
          'taken_at': op.takenAt?.toUtc().toIso8601String(),
          'is_late': op.isLate,
          'recorded_by': uid,
        }, onConflict: 'schedule_id,scheduled_at');
      });
}
