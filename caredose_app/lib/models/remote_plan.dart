import 'models.dart';

String _s(dynamic v) => v is String ? v : '';

class PlanSchedule {
  final String id, time;
  const PlanSchedule(this.id, this.time);
}

/// A server `medication_plans` row (with embedded medicine and schedules) as the app sees it.
class RemotePlan {
  final String id, name, dosage, meal, start, end, note;
  final List<PlanSchedule> schedules;
  const RemotePlan({
    required this.id,
    required this.name,
    required this.dosage,
    required this.meal,
    required this.start,
    required this.end,
    required this.note,
    required this.schedules,
  });

  factory RemotePlan.fromJson(Json j) {
    final m = j['medicines'] is Map ? Json.from(j['medicines'] as Map) : <String, dynamic>{};
    final trade = _s(m['trade_name']);
    final doctorNote = _s(j['doctor_note']);
    final rows = (j['medication_schedules'] is List ? j['medication_schedules'] as List : const []).whereType<Map>().where(
          // Weekday / interval schedules are not representable in Med.times yet.
          (r) => r['days_of_week'] == null && r['interval_days'] == null && _s(r['time_of_day']).length >= 5,
        );
    final byTime = <String, PlanSchedule>{};
    for (final r in rows) {
      final t = _s(r['time_of_day']).substring(0, 5);
      byTime.putIfAbsent(t, () => PlanSchedule(_s(r['id']), t));
    }
    return RemotePlan(
      id: _s(j['id']),
      name: trade.isNotEmpty ? trade : _s(m['generic_name']),
      dosage: _s(j['dose']),
      meal: _s(j['meal_relation']),
      start: _s(j['start_date']),
      end: _s(j['end_date']),
      note: doctorNote.isNotEmpty ? doctorNote : _s(m['warning']),
      schedules: byTime.values.toList()..sort((a, b) => a.time.compareTo(b.time)),
    );
  }

  Med toMed() => Med(
        id: id,
        name: name,
        dosage: dosage,
        meal: meal,
        times: [for (final s in schedules) s.time],
        start: start,
        end: end,
        note: note,
        // Not String.hashCode: that differs between runs, and the colour must not change.
        color: medColors[id.codeUnits.fold<int>(0, (a, c) => a + c) % medColors.length],
      );
}

/// A `medication_logs` row.
class RemoteLog {
  final String planId, scheduleId, status;
  final DateTime scheduledAt;
  final DateTime? takenAt;
  const RemoteLog({required this.planId, required this.scheduleId, required this.status, required this.scheduledAt, this.takenAt});

  factory RemoteLog.fromJson(Json j) => RemoteLog(
        planId: _s(j['plan_id']),
        scheduleId: _s(j['schedule_id']),
        status: _s(j['status']),
        scheduledAt: DateTime.parse(_s(j['scheduled_at'])),
        takenAt: j['taken_at'] is String ? DateTime.parse(j['taken_at'] as String) : null,
      );
}

/// A dose action waiting to be written to the server. [status] is taken | skipped | pending.
class LogOp {
  final String planId, scheduleId, status;
  final DateTime scheduledAt;
  final DateTime? takenAt;
  final bool isLate;
  const LogOp({
    required this.planId,
    required this.scheduleId,
    required this.status,
    required this.scheduledAt,
    this.takenAt,
    this.isLate = false,
  });

  Json toJson() => {
        'planId': planId,
        'scheduleId': scheduleId,
        'status': status,
        'scheduledAt': scheduledAt.toUtc().toIso8601String(),
        'takenAt': takenAt?.toUtc().toIso8601String(),
        'isLate': isLate,
      };

  factory LogOp.fromJson(Json j) => LogOp(
        planId: _s(j['planId']),
        scheduleId: _s(j['scheduleId']),
        status: _s(j['status']),
        scheduledAt: DateTime.parse(_s(j['scheduledAt'])),
        takenAt: j['takenAt'] is String ? DateTime.parse(j['takenAt'] as String) : null,
        isLate: j['isLate'] == true,
      );
}
