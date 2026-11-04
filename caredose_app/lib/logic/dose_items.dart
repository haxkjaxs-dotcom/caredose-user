import '../models/models.dart';

enum DoseStatus { taken, skipped, pending, missed }

String doseStatusLabel(DoseStatus s) {
  switch (s) {
    case DoseStatus.taken:
      return 'ทานแล้ว';
    case DoseStatus.skipped:
      return 'ข้าม';
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

/// All dose slots on [date], sorted by time then medicine name.
List<DoseItem> itemsFor(AppData d, String date, DateTime now) {
  final out = <DoseItem>[];
  for (final med in d.meds) {
    if (med.start.isNotEmpty && date.compareTo(med.start) < 0) continue;
    if (med.end.isNotEmpty && date.compareTo(med.end) > 0) continue;
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
