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
// RLS (can_see_patient) also shows an admin, doctor or caregiver account every patient they look after, so every read
// is pinned to the signed-in user's own patients row (patients.user_id); otherwise another patient's plans, logs and
// appointments would land on this phone as the user's own.
class SupabaseMedRepository implements MedRepository {
  SupabaseMedRepository(this._c);
  final SupabaseClient _c;

  @override
  Future<List<RemotePlan>> fetchPlans() => guardCall(() async {
        final uid = requireUserId(_c.auth.currentUser?.id);
        final rows = await _c
            .from('medication_plans')
            .select('*, patients!inner(user_id), medicines(generic_name,trade_name,warning), medication_schedules(id,time_of_day,days_of_week,interval_days)')
            .eq('status', 'active')
            .eq('patients.user_id', uid);
        return [for (final r in rows) RemotePlan.fromJson(Json.from(r))];
      });

  @override
  Future<List<RemoteLog>> fetchLogs(DateTime since) => guardCall(() async {
        final uid = requireUserId(_c.auth.currentUser?.id);
        final rows = await _c
            .from('medication_logs')
            .select('*, medication_plans!inner(patients!inner(user_id))')
            .eq('medication_plans.patients.user_id', uid)
            .gte('scheduled_at', since.toUtc().toIso8601String())
            .order('scheduled_at');
        return [for (final r in rows) RemoteLog.fromJson(Json.from(r))];
      });

  @override
  Future<List<RemoteAppt>> fetchAppointments() => guardCall(() async {
        final uid = requireUserId(_c.auth.currentUser?.id);
        final rows = await _c.from('appointments').select('*, patients!inner(user_id)').eq('patients.user_id', uid).order('appointment_at');
        return [for (final r in rows) RemoteAppt.fromJson(Json.from(r))];
      });

  @override
  Future<String> fetchDoctorName() => guardCall(() async {
        final uid = requireUserId(_c.auth.currentUser?.id);
        final rows = await _c.from('patients').select('doctor_name').eq('user_id', uid).limit(1);
        final v = rows.isEmpty ? null : rows.first['doctor_name'];
        return v is String ? v.trim() : '';
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
