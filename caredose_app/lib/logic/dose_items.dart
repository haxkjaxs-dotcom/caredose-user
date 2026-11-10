import '../models/models.dart';

enum DoseStatus { taken, skipped, pending, missed }

String doseStatusLabel(DoseStatus s) {
  switch (s) {
    case DoseStatus.taken:
      return 'ทานแล้ว';
    case DoseStatus.skipped:
      return 'ยังไม่ได้ทาน';
    case DoseStatus.pending:
      return 'รอทาน';
    case DoseStatus.missed:
      return 'เลยเวลา';
  }
}

class DoseItem {
  final Med med;
  final String time;
  final String key;
  final DoseLog? log;
  final DoseStatus status;
  const DoseItem({required this.med, required this.time, required this.key, required this.log, required this.status});
}

DateTime doseTime(String date, String time) => DateTime.parse('${date}T$time');

/// Whether [med] has doses on [date] (yyyy-MM-dd): inside start/end, then its day rule.
/// Weekdays are ISO (1 = Monday ... 7 = Sunday). Every-N-days counts whole days from `start`;
/// without a start date that rule cannot be counted, so it falls back to every day.
bool isDueOn(Med med, String date) {
  if (med.start.isNotEmpty && date.compareTo(med.start) < 0) return false;
  if (med.end.isNotEmpty && date.compareTo(med.end) > 0) return false;
  if (med.days.isNotEmpty) return med.days.contains(DateTime.parse(date).weekday);
  if (med.intervalDays >= 2 && med.start.isNotEmpty) {
    DateTime utc(String s) {
      final d = DateTime.parse(s);
      return DateTime.utc(d.year, d.month, d.day); // UTC: no daylight-saving hour can shift the day count
    }
    return utc(date).difference(utc(med.start)).inDays % med.intervalDays == 0;
  }
  return true;
}

/// All dose slots on [date], sorted by time then medicine name.
List<DoseItem> itemsFor(AppData d, String date, DateTime now) {
  final out = <DoseItem>[];
  for (final med in d.meds) {
    if (!isDueOn(med, date)) continue;
    for (final time in med.times) {
      final key = '${med.id}|$date|$time';
      final log = d.logs[key];
      final DoseStatus status;
      if (log != null) {
        status = log.status == 'skipped' ? DoseStatus.skipped : DoseStatus.taken;
      } else {
        status = doseTime(date, time).isBefore(now) ? DoseStatus.missed : DoseStatus.pending;
      }
      out.add(DoseItem(med: med, time: time, key: key, log: log, status: status));
    }
  }
  out.sort((a, b) {
    final c = a.time.compareTo(b.time);
    return c != 0 ? c : a.med.name.compareTo(b.med.name);
  });
  return out;
}
