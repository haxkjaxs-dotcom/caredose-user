import 'package:flutter/material.dart';

import '../logic/thai_date.dart';
import '../theme.dart';
import 'calendar_picker.dart';
import 'common.dart';

class DateRangePicker extends StatefulWidget {
  const DateRangePicker({super.key, required this.from, required this.to, required this.onFrom, required this.onTo});
  final String from, to;
  final ValueChanged<String> onFrom, onTo;

  @override
  State<DateRangePicker> createState() => _DateRangePickerState();
}

class _DateRangePickerState extends State<DateRangePicker> {
  bool editingFrom = true;

  void _choose(String date) {
    if (editingFrom) {
      widget.onFrom(date);
      setState(() => editingFrom = false);
    } else {
      widget.onTo(date);
    }
  }

  Widget _toggle(String title, String date, bool active, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: active ? tealTint : Colors.white,
            border: Border.all(color: active ? brand : stone300, width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: stone600)),
            Text(thDateShort(date), style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final valid = widget.from.compareTo(widget.to) <= 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _toggle('จากวันที่', widget.from, editingFrom, () => setState(() => editingFrom = true)),
      const SizedBox(height: 8),
      _toggle('ถึงวันที่', widget.to, !editingFrom, () => setState(() => editingFrom = false)),
      const SizedBox(height: 12),
      CalendarPicker(
        keyPrefix: 'range',
        date: editingFrom ? widget.from : widget.to,
        label: editingFrom ? 'เลือกวันเริ่มต้น' : 'เลือกวันสิ้นสุด',
        onChanged: _choose,
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: valid ? tealTint : const Color(0xFFFEF2F2),
          border: Border.all(color: valid ? const Color(0xFF5EEAD4) : const Color(0xFFEF4444), width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          Text(valid ? 'ช่วงวันที่ที่เลือก' : 'วันที่สิ้นสุดต้องไม่ก่อนวันที่เริ่ม',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: valid ? brandDark : const Color(0xFF7F1D1D))),
          if (valid) Text('${thDate(widget.from)} ถึง ${thDate(widget.to)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: brandDark)),
        ]),
      ),
    ]);
  }
}
