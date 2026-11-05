import '../logic/thai_date.dart';
import '../models/models.dart';

/// Applies a notification button (`taken` | `notyet` | `skip`) for dose [key].
/// `notyet` records no log; it only stops the repeat reminder for that dose.
({AppData data, Set<String> dismissed}) applyDoseAction(
  AppData d,
  Set<String> dismissed,
  String actionId,
  String key,
  DateTime now,
) {
  var data = d;
  var dis = {...dismissed};
  switch (actionId) {
    case 'taken':
    case 'skip':
      data = d.copyWith(logs: {
        ...d.logs,
        key: DoseLog(actionId == 'taken' ? 'taken' : 'skipped', now.toIso8601String()),
      });
    case 'notyet':
      dis.add(key);
    default:
      return (data: d, dismissed: dismissed);
  }
  final cutoff = dateKey(now.subtract(const Duration(days: 2)));
  dis.removeWhere((k) {
    final parts = k.split('|');
    return parts.length > 1 && parts[1].compareTo(cutoff) < 0;
  });
  return (data: data, dismissed: dis);
}
