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

  /// The plan's day rule (see Med.days / Med.intervalDays); the server writes the same rule on every row of a plan.
  final List<int> days;
  final int intervalDays;
  const RemotePlan({
    required this.id,
    required this.name,
    required this.dosage,
    required this.meal,
    required this.start,
    required this.end,
    required this.note,
    required this.schedules,
    this.days = const [],
    this.intervalDays = 0,
  });

  factory RemotePlan.fromJson(Json j) {
    final m = j['medicines'] is Map ? Json.from(j['medicines'] as Map) : <String, dynamic>{};
    final trade = _s(m['trade_name']);
    final doctorNote = _s(j['doctor_note']);
    final rows = (j['medication_schedules'] is List ? j['medication_schedules'] as List : const []).whereType<Map>().where(
          (r) => _s(r['time_of_day']).length >= 5,
        );
    final byTime = <String, PlanSchedule>{};
    final rowByTime = <String, Map>{};
    for (final r in rows) {
      final t = _s(r['time_of_day']).substring(0, 5);
      byTime.putIfAbsent(t, () => PlanSchedule(_s(r['id']), t));
      rowByTime.putIfAbsent(t, () => r);
    }
    // If rows ever disagree, the earliest time decides (same as the web).
    final rule = rowByTime.isEmpty ? const <String, dynamic>{} : rowByTime[(rowByTime.keys.toList()..sort()).first]!;
    return RemotePlan(
      id: _s(j['id']),
      name: trade.isNotEmpty ? trade : _s(m['generic_name']),
      dosage: _s(j['dose']),
      meal: _s(j['meal_relation']),
      start: _s(j['start_date']),
      end: _s(j['end_date']),
      note: doctorNote.isNotEmpty ? doctorNote : _s(m['warning']),
      schedules: byTime.values.toList()..sort((a, b) => a.time.compareTo(b.time)),
      days: sanitizeDays(rule['days_of_week']),
      intervalDays: sanitizeInterval(rule['interval_days']),
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
        days: days,
        intervalDays: intervalDays,
        // Not String.hashCode: that differs between runs, and the colour must not change.
        color: medColors[id.codeUnits.fold<int>(0, (a, c) => a + c) % medColors.length],
      );
}

/// An `appointments` row as the app shows it. The server status set is pending|scheduled|done|postponed|cancelled.
class RemoteAppt {
  final String id, place, dept, note, status;
  final DateTime at;
  const RemoteAppt({required this.id, required this.at, this.place = '', this.dept = '', this.note = '', this.status = 'pending'});

  factory RemoteAppt.fromJson(Json j) {
    final reason = _s(j['reason']).trim(), note = _s(j['note']).trim();
    return RemoteAppt(
      id: _s(j['id']),
      at: DateTime.parse(_s(j['appointment_at'])),
      place: _s(j['place']),
      dept: _s(j['department']),
      note: [reason, note].where((x) => x.isNotEmpty).join(' · '),
      status: _s(j['status']),
    );
  }

  /// Server status -> the app's appointment styles (see contacts_screen).
  static const _statusMap = {
    'pending': 'pending',
    'scheduled': 'confirmed',
    'done': 'done',
    'postponed': 'rescheduled',
    'cancelled': 'cancelled',
  };

  Appt toAppt() => Appt(
        id: id,
        at: at.toLocal().toIso8601String(),
        place: place,
        dept: dept,
        note: note,
        status: _statusMap[status] ?? 'pending',
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

  /// How many times the server answered "unknown error" for this op (the outbox gives up after a few).
  final int attempts;
  const LogOp({
    required this.planId,
    required this.scheduleId,
    required this.status,
    required this.scheduledAt,
    this.takenAt,
    this.isLate = false,
    this.attempts = 0,
  });

  LogOp withAttempts(int n) => LogOp(
        planId: planId,
        scheduleId: scheduleId,
        status: status,
        scheduledAt: scheduledAt,
        takenAt: takenAt,
        isLate: isLate,
        attempts: n,
      );

  Json toJson() => {
        'planId': planId,
        'scheduleId': scheduleId,
        'status': status,
        'scheduledAt': scheduledAt.toUtc().toIso8601String(),
        'takenAt': takenAt?.toUtc().toIso8601String(),
        'isLate': isLate,
        'attempts': attempts,
      };

  factory LogOp.fromJson(Json j) => LogOp(
        planId: _s(j['planId']),
        scheduleId: _s(j['scheduleId']),
        status: _s(j['status']),
        scheduledAt: DateTime.parse(_s(j['scheduledAt'])),
        takenAt: j['takenAt'] is String ? DateTime.parse(j['takenAt'] as String) : null,
        isLate: j['isLate'] == true,
        attempts: j['attempts'] is int ? j['attempts'] as int : 0,
      );
}
