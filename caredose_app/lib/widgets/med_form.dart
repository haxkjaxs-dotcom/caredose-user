import 'package:flutter/material.dart';

import '../logic/thai_date.dart';
import '../models/models.dart';
import 'common.dart';

/// Returns the Thai error message, or null when [m] can be saved.
String? validateMed(Med m) {
  if (m.name.trim().isEmpty) return 'กรุณากรอกชื่อยา';
  if (m.times.isEmpty || m.times.any((t) => t.isEmpty)) return 'กรุณาระบุเวลาเตือน';
  if (m.end.isNotEmpty && m.end.compareTo(m.start) < 0) return 'วันที่สิ้นสุดต้องไม่ก่อนวันที่เริ่ม';
  return null;
}

class MedForm extends StatefulWidget {
  const MedForm({super.key, required this.initial, required this.count, required this.today, required this.onSave});
  final Med? initial;
  final int count;
  final String today;
  final ValueChanged<Med> onSave;

  @override
  State<MedForm> createState() => _MedFormState();
}

class _MedFormState extends State<MedForm> {
  late Med m;
  late final TextEditingController name, dosage, note;
  String err = '';

  @override
  void initState() {
    super.initState();
    m = widget.initial ??
        Med(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
          name: '',
          dosage: '1 เม็ด',
          times: const ['08:00'],
          start: widget.today,
          color: medColors[widget.count % medColors.length],
        );
    name = TextEditingController(text: m.name);
    dosage = TextEditingController(text: m.dosage);
    note = TextEditingController(text: m.note);
  }

  @override
  void dispose() {
    name.dispose();
    dosage.dispose();
    note.dispose();
    super.dispose();
  }

  Future<String?> _pickTime(String current) async {
    final parts = current.split(':');
    final initial = parts.length == 2
        ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 8, minute: int.tryParse(parts[1]) ?? 0)
        : const TimeOfDay(hour: 8, minute: 0);
    final t = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<String?> _pickDate(String current) async {
    final base = DateTime.tryParse(current) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    return d == null ? null : dateKey(d);
  }

  void _submit() {
    final candidate = m.copyWith(name: name.text, dosage: dosage.text, note: note.text);
    final e = validateMed(candidate);
    if (e != null) {
      setState(() => err = e);
      return;
    }
    widget.onSave(candidate.copyWith(name: candidate.name.trim(), times: ({...candidate.times}.toList()..sort())));
  }

  Widget _box(String text, VoidCallback onTap, {Widget? trailing}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFA8A29E), width: 2), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [Expanded(child: Text(text)), ?trailing]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledField('ชื่อยา (จำเป็น)', child: TextField(controller: name)),
        const SizedBox(height: 16),
        LabeledField('ปริมาณ เช่น 1 เม็ด, 5 ml', child: TextField(controller: dosage)),
        const SizedBox(height: 16),
        const Text('เวลาเตือน', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        for (var i = 0; i < m.times.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: _box(m.times[i].isEmpty ? 'เลือกเวลา' : m.times[i], () async {
                  final t = await _pickTime(m.times[i]);
                  if (t != null) setState(() => m = m.copyWith(times: [for (var j = 0; j < m.times.length; j++) j == i ? t : m.times[j]]));
                }),
              ),
              if (m.times.length > 1) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  style: dangerStyle(),
                  onPressed: () => setState(() => m = m.copyWith(times: [for (var j = 0; j < m.times.length; j++) if (j != i) m.times[j]])),
                  child: const Text('ลบ'),
                ),
              ],
            ]),
          ),
        OutlinedButton(onPressed: () => setState(() => m = m.copyWith(times: [...m.times, '12:00'])), child: const Text('+ เพิ่มเวลา')),
        const SizedBox(height: 16),
        LabeledField(
          'ก่อน/หลังอาหาร',
          child: DropdownButtonFormField<String>(
            initialValue: m.meal,
            items: const [
              DropdownMenuItem(value: '', child: Text('ไม่ระบุ')),
              DropdownMenuItem(value: 'ก่อนอาหาร', child: Text('ก่อนอาหาร')),
              DropdownMenuItem(value: 'หลังอาหาร', child: Text('หลังอาหาร')),
              DropdownMenuItem(value: 'พร้อมอาหาร', child: Text('พร้อมอาหาร')),
            ],
            onChanged: (v) => setState(() => m = m.copyWith(meal: v ?? '')),
          ),
        ),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: LabeledField('วันที่เริ่ม', child: _box(m.start.isEmpty ? 'เลือกวันที่' : thDateShort(m.start), () async {
              final d = await _pickDate(m.start);
              if (d != null) setState(() => m = m.copyWith(start: d));
            })),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LabeledField(
              'วันที่สิ้นสุด',
              child: _box(
                m.end.isEmpty ? 'ไม่ระบุ' : thDateShort(m.end),
                () async {
                  final d = await _pickDate(m.end.isEmpty ? m.start : m.end);
                  if (d != null) setState(() => m = m.copyWith(end: d));
                },
                trailing: m.end.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'ล้างวันที่สิ้นสุด',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => m = m.copyWith(end: '')),
                      ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        LabeledField('หมายเหตุ', child: TextField(controller: note, maxLines: 2)),
        if (err.isNotEmpty) ...[const SizedBox(height: 16), ErrorBox(err)],
        const SizedBox(height: 16),
        FilledButton(onPressed: _submit, child: const Text('บันทึก')),
      ],
    );
  }
}
