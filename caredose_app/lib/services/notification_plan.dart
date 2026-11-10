import '../logic/dose_items.dart';
import '../logic/thai_date.dart';
import '../models/models.dart';

class PlannedNotification {
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload; // dose log key
  final bool isRepeat;
  const PlannedNotification({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
    required this.isRepeat,
  });
}

/// Stable 31-bit-safe id per dose key; odd ids are repeat reminders.
int notificationId(String key, {required bool repeat}) {
  var h = 0x811c9dc5; // FNV-1a 32-bit
  for (final c in key.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return (h & 0x3fffffff) * 2 + (repeat ? 1 : 0);
}

List<PlannedNotification> planNotifications(
  AppData d,
  Set<String> dismissed,
  DateTime now, {
  int maxDays = 14,
  int maxCount = 60,
}) {
  if (!d.notify) return const [];
  final out = <PlannedNotification>[];
  for (var offset = 0; offset < maxDays; offset++) {
    final date = dateKey(DateTime(now.year, now.month, now.day + offset));
    for (final med in d.meds) {
      if (!isDueOn(med, date)) continue;
      for (final time in med.times) {
        final key = '${med.id}|$date|$time';
        if (d.logs.containsKey(key)) continue;
        final at = doseTime(date, time);
        final body = '${med.name} ${med.dosage}${med.meal.isEmpty ? '' : ' • ${med.meal}'}';
        if (at.isAfter(now)) {
          out.add(PlannedNotification(
              id: notificationId(key, repeat: false), at: at, title: 'ถึงเวลาทานยา', body: body, payload: key, isRepeat: false));
        }
        final repeatAt = at.add(const Duration(minutes: 15));
        if (d.repeatReminder && !dismissed.contains(key) && repeatAt.isAfter(now)) {
          out.add(PlannedNotification(
              id: notificationId(key, repeat: true),
              at: repeatAt,
              title: 'เตือนอีกครั้ง: ยังไม่ได้ทานยา',
              body: body,
              payload: key,
              isRepeat: true));
        }
      }
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out.length > maxCount ? out.sublist(0, maxCount) : out;
}
