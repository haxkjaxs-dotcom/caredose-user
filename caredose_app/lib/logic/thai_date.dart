const _weekdays = ['อาทิตย์', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์'];
const _months = [
  'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
  'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
];
const _monthsShort = [
  'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
];

String _pad(int n) => n.toString().padLeft(2, '0');

String dateKey(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

String todayKey(DateTime now) => dateKey(now);

DateTime _parse(String key) => DateTime.parse('${key}T00:00:00');

String thDate(String key) {
  final d = _parse(key);
  // DateTime.weekday: Monday=1..Sunday=7
  return 'วัน${_weekdays[d.weekday % 7]}ที่ ${d.day} ${_months[d.month - 1]} ${d.year + 543}';
}

String thDateShort(String key) {
  final d = _parse(key);
  return '${d.day} ${_monthsShort[d.month - 1]} ${d.year + 543}';
}

String thMonthYear(int year, int month) => '${_months[month - 1]} ${year + 543}';

String thTime(DateTime d) => '${_pad(d.hour)}:${_pad(d.minute)}';
