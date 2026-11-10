import 'package:caredose/models/models.dart';
import 'package:caredose/models/remote_plan.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> planJson({
  String id = 'plan-1',
  Map<String, dynamic>? medicines = const {'generic_name': 'Amlodipine', 'trade_name': 'Norvasc', 'warning': 'ระวังเวียนศีรษะ'},
  String? doctorNote,
  String? endDate,
  List<Map<String, dynamic>>? schedules,
}) =>
    {
      'id': id,
      'patient_id': 'p1',
      'medicine_id': 'm1',
      'dose': '1 เม็ด',
      'quantity': 30,
      'meal_relation': 'หลังอาหาร',
      'start_date': '2026-11-04',
      'end_date': endDate,
      'status': 'active',
      'doctor_note': doctorNote,
      'medicines': medicines,
      'medication_schedules': schedules ??
          [
            {'id': 's2', 'time_of_day': '18:00:00', 'days_of_week': null, 'interval_days': null},
            {'id': 's1', 'time_of_day': '08:00:00', 'days_of_week': null, 'interval_days': null},
          ],
    };

void main() {
  group('RemotePlan.fromJson', () {
    test('maps a normal plan', () {
      final p = RemotePlan.fromJson(planJson(doctorNote: 'พบแพทย์ถ้าผื่นขึ้น'));
      expect(p.id, 'plan-1');
      expect(p.name, 'Norvasc');
      expect(p.dosage, '1 เม็ด');
      expect(p.meal, 'หลังอาหาร');
      expect(p.start, '2026-11-04');
      expect(p.end, '');
      expect(p.note, 'พบแพทย์ถ้าผื่นขึ้น');
      expect(p.schedules.map((s) => (s.id, s.time)), [('s1', '08:00'), ('s2', '18:00')]);
    });

    test('falls back to generic name and medicine warning', () {
      final p = RemotePlan.fromJson(planJson(medicines: {'generic_name': 'Amlodipine', 'trade_name': '', 'warning': 'ระวัง'}, doctorNote: ''));
      expect(p.name, 'Amlodipine');
      expect(p.note, 'ระวัง');
    });

    test('missing medicine and null fields do not throw', () {
      final j = planJson(medicines: null)..['meal_relation'] = null;
      final p = RemotePlan.fromJson(j);
      expect(p.name, '');
      expect(p.meal, '');
      expect(p.note, '');
    });

    test('end date is kept when set', () {
      expect(RemotePlan.fromJson(planJson(endDate: '2026-12-01')).end, '2026-12-01');
    });

    test('rows that carry a day rule are kept like any other (phase 2; they used to be skipped)', () {
      final p = RemotePlan.fromJson(planJson(schedules: [
        {'id': 'a', 'time_of_day': '07:00:00', 'days_of_week': [1, 3], 'interval_days': null},
        {'id': 'b', 'time_of_day': '09:00:00', 'days_of_week': null, 'interval_days': 2},
        {'id': 'c', 'time_of_day': '12:30:00', 'days_of_week': null, 'interval_days': null},
      ]));
      expect(p.schedules.map((s) => s.id), ['a', 'b', 'c']);
    });

    test('duplicate times keep only the first row', () {
      final p = RemotePlan.fromJson(planJson(schedules: [
        {'id': 'a', 'time_of_day': '08:00:00', 'days_of_week': null, 'interval_days': null},
        {'id': 'b', 'time_of_day': '08:00:00', 'days_of_week': null, 'interval_days': null},
      ]));
      expect(p.schedules.map((s) => s.id), ['a']);
    });
  });

  group('toMed', () {
    test('carries fields and a stable colour per plan id', () {
      final m = RemotePlan.fromJson(planJson()).toMed();
      expect(m.id, 'plan-1');
      expect(m.name, 'Norvasc');
      expect(m.times, ['08:00', '18:00']);
      expect(medColors, contains(m.color));
      expect(RemotePlan.fromJson(planJson()).toMed().color, m.color);
    });

    test('colour is the code-unit sum modulo the palette size', () {
      final sum = 'ab'.codeUnits.fold<int>(0, (a, c) => a + c);
      expect(RemotePlan.fromJson(planJson(id: 'ab')).toMed().color, medColors[sum % medColors.length]);
    });
  });

  group('logs', () {
    test('LogOp JSON round-trips as UTC instants', () {
      final op = LogOp(
        planId: 'p',
        scheduleId: 's',
        status: 'taken',
        scheduledAt: DateTime(2026, 11, 4, 8),
        takenAt: DateTime(2026, 11, 4, 8, 20),
        isLate: true,
      );
      final j = op.toJson();
      expect(j['scheduledAt'], DateTime(2026, 11, 4, 8).toUtc().toIso8601String());
      final back = LogOp.fromJson(j);
      expect(back.scheduledAt.isAtSameMomentAs(op.scheduledAt), true);
      expect(back.takenAt!.isAtSameMomentAs(op.takenAt!), true);
      expect((back.planId, back.scheduleId, back.status, back.isLate), ('p', 's', 'taken', true));
    });

    test('LogOp with no takenAt round-trips', () {
      final op = LogOp(planId: 'p', scheduleId: 's', status: 'skipped', scheduledAt: DateTime.utc(2026, 11, 4, 1), isLate: false);
      final back = LogOp.fromJson(op.toJson());
      expect(back.takenAt, isNull);
      expect(back.scheduledAt, op.scheduledAt);
    });

    test('RemoteLog.fromJson parses a medication_logs row', () {
      final l = RemoteLog.fromJson({
        'plan_id': 'p',
        'schedule_id': 's',
        'scheduled_at': '2026-11-04T01:00:00+00:00',
        'status': 'taken',
        'taken_at': '2026-11-04T08:20:00+07:00',
      });
      expect((l.planId, l.scheduleId, l.status), ('p', 's', 'taken'));
      expect(l.scheduledAt, DateTime.utc(2026, 11, 4, 1));
      expect(l.takenAt, DateTime.utc(2026, 11, 4, 1, 20));
    });
  });

  group('RemotePlan rules', () {
    test('weekday and interval rows are no longer skipped; the rule is read', () {
      final p = RemotePlan.fromJson(planJson(schedules: [
        {'id': 's1', 'time_of_day': '08:00:00', 'days_of_week': [1, 3], 'interval_days': null},
        {'id': 's2', 'time_of_day': '20:00:00', 'days_of_week': [1, 3], 'interval_days': null},
      ]));
      expect(p.schedules.map((s) => s.time), ['08:00', '20:00']);
      expect(p.days, [1, 3]);
      expect(p.intervalDays, 0);
      final m = p.toMed();
      expect([m.days, m.intervalDays], [[1, 3], 0]);
    });
    test('interval rule, and interval 1 is treated as every day', () {
      expect(RemotePlan.fromJson(planJson(schedules: [
        {'id': 's1', 'time_of_day': '08:00:00', 'days_of_week': null, 'interval_days': 2},
      ])).intervalDays, 2);
      expect(RemotePlan.fromJson(planJson(schedules: [
        {'id': 's1', 'time_of_day': '08:00:00', 'days_of_week': null, 'interval_days': 1},
      ])).intervalDays, 0);
    });
    test('rows that disagree: the earliest time wins', () {
      final p = RemotePlan.fromJson(planJson(schedules: [
        {'id': 's2', 'time_of_day': '20:00:00', 'days_of_week': null, 'interval_days': 2},
        {'id': 's1', 'time_of_day': '08:00:00', 'days_of_week': [2], 'interval_days': null},
      ]));
      expect([p.days, p.intervalDays], [[2], 0]);
    });
    test('no rule is every day', () {
      final p = RemotePlan.fromJson(planJson());
      expect([p.days, p.intervalDays], [<int>[], 0]);
    });
  });
}
