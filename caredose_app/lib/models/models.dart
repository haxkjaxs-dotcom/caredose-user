import '../logic/thai_date.dart';

typedef Json = Map<String, dynamic>;

String _str(dynamic v, [String d = '']) => v is String ? v : d;
bool _bool(dynamic v, bool d) => v is bool ? v : d;
double _num(dynamic v) => v is num ? v.toDouble() : 0;
List<T> _list<T>(dynamic v, T Function(Json) f) =>
    v is List ? v.whereType<Map>().map((e) => f(Json.from(e))).toList() : <T>[];

const medColors = ['#e9b44c', '#7fb7a4', '#e07a5f', '#8aa1d6', '#c58fc2'];

final _hhmm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

bool _validDate(String s) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return false;
  final d = DateTime.tryParse(s);
  return d != null && dateKey(d) == s;
}

class Med {
  final String id, name, dosage, meal, start, end, note, color;
  final List<String> times;
  const Med({
    required this.id,
    required this.name,
    this.dosage = '',
    this.meal = '',
    this.times = const [],
    this.start = '',
    this.end = '',
    this.note = '',
    this.color = '#e9b44c',
  });

  factory Med.fromJson(Json j) => Med(
        id: _str(j['id']),
        name: _str(j['name']),
        dosage: _str(j['dosage']),
        meal: _str(j['meal']),
        // Malformed values would make DateTime.parse throw in itemsFor/planNotifications.
        times: j['times'] is List ? (j['times'] as List).whereType<String>().where(_hhmm.hasMatch).toList() : <String>[],
        start: _validDate(_str(j['start'])) ? _str(j['start']) : '',
        end: _validDate(_str(j['end'])) ? _str(j['end']) : '',
        note: _str(j['note']),
        color: _str(j['color'], '#e9b44c'),
      );

  Json toJson() => {
        'id': id, 'name': name, 'dosage': dosage, 'meal': meal, 'times': times,
        'start': start, 'end': end, 'note': note, 'color': color,
      };

  Med copyWith({String? name, String? dosage, String? meal, List<String>? times, String? start, String? end, String? note}) => Med(
        id: id,
        name: name ?? this.name,
        dosage: dosage ?? this.dosage,
        meal: meal ?? this.meal,
        times: times ?? this.times,
        start: start ?? this.start,
        end: end ?? this.end,
        note: note ?? this.note,
        color: color,
      );
}

class DoseLog {
  final String status; // 'taken' | 'skipped'
  final String at; // ISO-8601
  const DoseLog(this.status, this.at);
  factory DoseLog.fromJson(Json j) => DoseLog(_str(j['status'], 'taken'), _str(j['at']));
  Json toJson() => {'status': status, 'at': at};
}

class Doctor {
  final String id, name, spec, phone;
  const Doctor({required this.id, required this.name, this.spec = '', this.phone = ''});
  factory Doctor.fromJson(Json j) =>
      Doctor(id: _str(j['id']), name: _str(j['name']), spec: _str(j['spec']), phone: _str(j['phone']));
  Json toJson() => {'id': id, 'name': name, 'spec': spec, 'phone': phone};
}

class Relative {
  final String id, name, rel, phone;
  const Relative({required this.id, required this.name, this.rel = '', this.phone = ''});
  factory Relative.fromJson(Json j) =>
      Relative(id: _str(j['id']), name: _str(j['name']), rel: _str(j['rel']), phone: _str(j['phone']));
  Json toJson() => {'id': id, 'name': name, 'rel': rel, 'phone': phone};
}

class Appt {
  final String id, at, place, dept, note;
  final String? status, previousAt, statusNote; // status: pending|confirmed|rescheduled|cancelled
  const Appt({
    required this.id,
    required this.at,
    this.place = '',
    this.dept = '',
    this.note = '',
    this.status,
    this.previousAt,
    this.statusNote,
  });
  factory Appt.fromJson(Json j) => Appt(
        id: _str(j['id']),
        at: _str(j['at']),
        place: _str(j['place']),
        dept: _str(j['dept']),
        note: _str(j['note']),
        status: j['status'] is String ? j['status'] as String : null,
        previousAt: j['previousAt'] is String ? j['previousAt'] as String : null,
        statusNote: j['statusNote'] is String ? j['statusNote'] as String : null,
      );
  Json toJson() => {
        'id': id, 'at': at, 'place': place, 'dept': dept, 'note': note,
        if (status != null) 'status': status,
        if (previousAt != null) 'previousAt': previousAt,
        if (statusNote != null) 'statusNote': statusNote,
      };
}

class BmiRecord {
  final String id, cat, at;
  final double w, h, v;
  const BmiRecord({required this.id, required this.w, required this.h, required this.v, required this.cat, required this.at});
  factory BmiRecord.fromJson(Json j) => BmiRecord(
        id: _str(j['id']), w: _num(j['w']), h: _num(j['h']), v: _num(j['v']), cat: _str(j['cat']), at: _str(j['at']));
  Json toJson() => {'id': id, 'w': w, 'h': h, 'v': v, 'cat': cat, 'at': at};
}

class AppData {
  final String patient, size, notifyChannel, verifiedPhone;
  final List<Med> meds;
  final Map<String, DoseLog> logs;
  final List<Doctor> doctors;
  final List<Relative> relatives;
  final List<Appt> appts;
  final List<BmiRecord> bmis;
  final bool notify, repeatReminder;

  const AppData({
    this.patient = '',
    this.meds = const [],
    this.logs = const {},
    this.doctors = const [],
    this.relatives = const [],
    this.appts = const [],
    this.bmis = const [],
    this.size = 'normal',
    this.notify = true,
    this.notifyChannel = 'app',
    this.repeatReminder = true,
    this.verifiedPhone = '',
  });

  factory AppData.seed(DateTime now) {
    final today = dateKey(now);
    return AppData(
      patient: 'คุณแม่สมศรี',
      size: 'normal',
      notify: true,
      notifyChannel: 'app',
      repeatReminder: true,
      verifiedPhone: '081-234-5678',
      meds: [
        Med(id: 'm1', name: 'ยาลดความดัน', dosage: '1 เม็ด', meal: 'หลังอาหาร', times: const ['08:00'], start: today, note: 'ทานพร้อมน้ำเปล่า', color: medColors[0]),
        Med(id: 'm2', name: 'ยาเบาหวาน', dosage: '1 เม็ด', meal: 'ก่อนอาหาร', times: const ['08:00', '18:00'], start: today, color: medColors[1]),
        Med(id: 'm3', name: 'แคลเซียม', dosage: '2 เม็ด', meal: 'หลังอาหาร', times: const ['12:30', '21:00'], start: today, color: medColors[2]),
      ],
      doctors: const [Doctor(id: 'd1', name: 'นพ.วิชัย ใจดี', spec: 'อายุรกรรม / โรคความดัน', phone: '021234567')],
      relatives: const [Relative(id: 'r1', name: 'สมชาย', rel: 'ลูกชาย', phone: '0812345678')],
      appts: [
        Appt(
          id: 'a1',
          at: '${dateKey(now.add(const Duration(days: 5)))}T09:30',
          place: 'โรงพยาบาลศิริราช',
          dept: 'อายุรกรรม',
          note: 'งดน้ำและอาหารก่อนตรวจ 8 ชั่วโมง',
          status: 'confirmed',
        ),
      ],
    );
  }

  factory AppData.fromJson(Json j) {
    final logs = <String, DoseLog>{};
    if (j['logs'] is Map) {
      (j['logs'] as Map).forEach((k, v) {
        if (k is String && v is Map) logs[k] = DoseLog.fromJson(Json.from(v));
      });
    }
    return AppData(
      patient: _str(j['patient']),
      meds: _list(j['meds'], Med.fromJson),
      logs: logs,
      doctors: _list(j['doctors'], Doctor.fromJson),
      relatives: _list(j['relatives'], Relative.fromJson),
      appts: _list(j['appts'], Appt.fromJson),
      bmis: _list(j['bmis'], BmiRecord.fromJson),
      size: _str(j['size'], 'normal'),
      notify: _bool(j['notify'], true),
      notifyChannel: _str(j['notifyChannel'], 'app'),
      repeatReminder: _bool(j['repeatReminder'], true),
      verifiedPhone: _str(j['verifiedPhone']),
    );
  }

  Json toJson() => {
        'patient': patient,
        'meds': meds.map((e) => e.toJson()).toList(),
        'logs': logs.map((k, v) => MapEntry(k, v.toJson())),
        'doctors': doctors.map((e) => e.toJson()).toList(),
        'relatives': relatives.map((e) => e.toJson()).toList(),
        'appts': appts.map((e) => e.toJson()).toList(),
        'bmis': bmis.map((e) => e.toJson()).toList(),
        'size': size,
        'notify': notify,
        'notifyChannel': notifyChannel,
        'repeatReminder': repeatReminder,
        'verifiedPhone': verifiedPhone,
      };

  AppData copyWith({
    String? patient,
    List<Med>? meds,
    Map<String, DoseLog>? logs,
    List<Doctor>? doctors,
    List<Relative>? relatives,
    List<Appt>? appts,
    List<BmiRecord>? bmis,
    String? size,
    bool? notify,
    String? notifyChannel,
    bool? repeatReminder,
    String? verifiedPhone,
  }) =>
      AppData(
        patient: patient ?? this.patient,
        meds: meds ?? this.meds,
        logs: logs ?? this.logs,
        doctors: doctors ?? this.doctors,
        relatives: relatives ?? this.relatives,
        appts: appts ?? this.appts,
        bmis: bmis ?? this.bmis,
        size: size ?? this.size,
        notify: notify ?? this.notify,
        notifyChannel: notifyChannel ?? this.notifyChannel,
        repeatReminder: repeatReminder ?? this.repeatReminder,
        verifiedPhone: verifiedPhone ?? this.verifiedPhone,
      );
}
