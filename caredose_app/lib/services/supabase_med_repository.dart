import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../models/remote_plan.dart';
import 'auth_repository.dart';
import 'med_repository.dart';
import 'supabase_auth_repository.dart' show guardCall;

/// No signed-in user (e.g. the server ended the session) must not drop queued records:
/// reported as a network failure so they wait for the next sign-in.
String requireUserId(String? uid) {
  if (uid == null) throw const AuthFailure(AuthFailureKind.network);
  return uid;
}

// Thin network wrapper, no unit tests: all mapping logic lives in remote_plan.dart.
class SupabaseMedRepository implements MedRepository {
  SupabaseMedRepository(this._c);
  final SupabaseClient _c;

  @override
  Future<List<RemotePlan>> fetchPlans() => guardCall(() async {
        final rows = await _c
            .from('medication_plans')
            .select('*, medicines(generic_name,trade_name,warning), medication_schedules(id,time_of_day,days_of_week,interval_days)')
            .eq('status', 'active');
        return [for (final r in rows) RemotePlan.fromJson(Json.from(r))];
      });

  @override
  Future<List<RemoteLog>> fetchLogs(DateTime since) => guardCall(() async {
        final rows = await _c
            .from('medication_logs')
            .select()
            .gte('scheduled_at', since.toUtc().toIso8601String())
            .order('scheduled_at');
        return [for (final r in rows) RemoteLog.fromJson(Json.from(r))];
      });

  @override
  Future<void> upsertLog(LogOp op) => guardCall(() async {
        final uid = requireUserId(_c.auth.currentUser?.id);
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
