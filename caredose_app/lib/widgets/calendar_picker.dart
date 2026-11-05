import 'package:flutter/material.dart';

import '../logic/thai_date.dart';
import '../theme.dart';
import 'common.dart';

class CalendarMeta {
  final String label;
  final Color bg, fg, border;
  const CalendarMeta(this.label, this.bg, this.fg, this.border);
}

const _weekdayHeads = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];

class CalendarPicker extends StatefulWidget {
  const CalendarPicker({
    super.key,
    required this.date,
    required this.onChanged,
    required this.keyPrefix,
    this.label = 'เลือกวันที่',
    this.dayMeta,
  });
  final String date; // yyyy-MM-dd
  final ValueChanged<String> onChanged;
  final String keyPrefix; // day cells get ValueKey('<prefix>-day-<yyyy-MM-dd>')
  final String label;
  final CalendarMeta? Function(String date)? dayMeta;

  @override
  State<CalendarPicker> createState() => _CalendarPickerState();
}

class _CalendarPickerState extends State<CalendarPicker> {
  late DateTime view;

  DateTime _monthOf(String date) {
    final d = DateTime.parse(date);
    return DateTime(d.year, d.month);
  }

  @override
  void initState() {
    super.initState();
    view = _monthOf(widget.date);
  }

  @override
  void didUpdateWidget(CalendarPicker old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date) view = _monthOf(widget.date);
  }

  Widget _cell(int day) {
    final value = dateKey(DateTime(view.year, view.month, day));
    final active = value == widget.date;
    final meta = widget.dayMeta?.call(value);
    final bg = active ? brand : (meta?.bg ?? const Color(0xFFFAFAF9));
    final fg = active ? Colors.white : (meta?.fg ?? ink);
    final border = active ? brand : (meta?.border ?? const Color(0xFFE7E5E4));
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        button: true,
        selected: active,
        label: '$day ${meta?.label ?? ''}${active ? ' วันที่เลือก' : ''}',
        child: InkWell(
          key: ValueKey('${widget.keyPrefix}-day-$value'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onChanged(value),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            decoration: BoxDecoration(color: bg, border: Border.all(color: border, width: 2), borderRadius: BorderRadius.circular(12)),
            child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              FittedBox(fit: BoxFit.scaleDown, child: Text(active ? '✓ $day' : '$day', style: TextStyle(color: fg, fontWeight: FontWeight.bold))),
              if (meta != null) FittedBox(fit: BoxFit.scaleDown, child: Text(meta.label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(view.year, view.month, 1).weekday % 7; // Sunday = 0
    final days = DateTime(view.year, view.month + 1, 0).day;
    final cells = <Widget>[
      for (var i = 0; i < first; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++) _cell(d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: stone300, width: 2), borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Row(children: [
            IconButton(
              tooltip: 'เดือนก่อนหน้า',
              onPressed: () => setState(() => view = DateTime(view.year, view.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(thMonthYear(view.year, view.month), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              tooltip: 'เดือนถัดไป',
              onPressed: () => setState(() => view = DateTime(view.year, view.month + 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            for (final h in _weekdayHeads)
              Expanded(child: Text(h, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: stone600))),
          ]),
          const SizedBox(height: 4),
          for (var r = 0; r < cells.length; r += 7)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final c in cells.sublist(r, r + 7)) Expanded(child: c)]),
            ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: tealTint, borderRadius: BorderRadius.circular(12)),
            child: Text('เลือกแล้ว: ${thDate(widget.date)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: brandDark)),
          ),
        ]),
      ),
    ]);
  }
}
