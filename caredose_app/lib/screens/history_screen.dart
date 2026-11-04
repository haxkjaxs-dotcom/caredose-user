import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/dose_items.dart';
import '../logic/thai_date.dart';
import '../services/csv_export.dart';
import '../state/app_state.dart';
import '../widgets/calendar_picker.dart';
import '../widgets/common.dart';
import '../widgets/date_range_picker.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? date, from, to;

  CalendarMeta? _daySummary(AppState s, String day) {
    final items = itemsFor(s.data, day, s.now);
    if (items.isEmpty) return const CalendarMeta('ไม่มี', Color(0xFFF5F5F4), stone600, stone300);
    if (items.any((i) => i.status == DoseStatus.missed)) return const CalendarMeta('พลาด', Color(0xFFFEE2E2), Color(0xFF7F1D1D), Color(0xFFEF4444));
    if (items.any((i) => i.status == DoseStatus.skipped)) return const CalendarMeta('ข้าม', Color(0xFFDBEAFE), Color(0xFF1E3A8A), Color(0xFF3B82F6));
    if (items.every((i) => i.status == DoseStatus.taken)) return const CalendarMeta('ครบ', Color(0xFFDCFCE7), Color(0xFF14532D), Color(0xFF16A34A));
    return const CalendarMeta('รอทาน', Color(0xFFFEF3C7), Color(0xFF78350F), Color(0xFFD97706));
  }

  Future<void> _export(AppState s, String f, String t) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await shareCsv(buildCsv(s.data, f, t, s.now), f, t);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('ส่งออกไม่สำเร็จ')));
    }
  }

  Widget _legend(String bold, String rest, Color color) => Text.rich(TextSpan(children: [
        TextSpan(text: bold, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        TextSpan(text: ' = $rest'),
      ]), style: const TextStyle(fontSize: 14));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final today = todayKey(s.now);
    final day = date ?? today;
    final f = from ?? today;
    final t = to ?? today;
    final items = itemsFor(s.data, day, s.now);
    int count(DoseStatus st) => items.where((i) => i.status == st).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CalendarPicker(
            keyPrefix: 'hist',
            date: day,
            label: 'เลือกวันที่ดูประวัติ',
            onChanged: (v) => setState(() => date = v),
            dayMeta: (v) => _daySummary(s, v),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 24, runSpacing: 4, children: [
            _legend('ครบ', 'ทานครบแล้ว', const Color(0xFF166534)),
            _legend('รอทาน', 'ยังไม่ถึงเวลา', const Color(0xFF92400E)),
            _legend('พลาด', 'เลยเวลา', const Color(0xFF991B1B)),
            _legend('ข้าม', 'ไม่ได้ทาน', const Color(0xFF1E40AF)),
            _legend('ไม่มี', 'ไม่มีรายการยา', stone600),
          ]),
        ]),
      ),
      const SizedBox(height: 20),
      Row(children: [
        for (final st in [DoseStatus.taken, DoseStatus.pending, DoseStatus.skipped, DoseStatus.missed])
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: statusStyle(st).bg,
                border: Border.all(color: statusStyle(st).border, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: DefaultTextStyle(
                style: TextStyle(color: statusStyle(st).fg, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                child: Column(children: [
                  Text('${count(st)}', style: const TextStyle(fontSize: 26, height: 1.1)),
                  FittedBox(fit: BoxFit.scaleDown, child: Text(doseStatusLabel(st), style: const TextStyle(fontSize: 12))),
                ]),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 20),
      if (items.isEmpty)
        const AppCard(
          child: Column(children: [
            Text('ไม่มีรายการยาในวันนี้', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('เลือกวันอื่นจากปฏิทินเพื่อดูประวัติ', style: TextStyle(color: stone600)),
          ]),
        ),
      for (final i in items) ...[
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.med.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(i.med.dosage, style: const TextStyle(fontSize: 14)),
                ]),
              ),
              const SizedBox(width: 8),
              StatusBadge(i.status),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFAFAF9), borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Expanded(child: _kv('เวลาที่กำหนด', '${i.time} น.')),
                Expanded(child: _kv('เวลาที่ทานจริง', i.log == null ? 'ยังไม่มีข้อมูล' : '${thTime(DateTime.parse(i.log!.at))} น.')),
              ]),
            ),
            if (i.med.note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'หมายเหตุ: ', style: TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: i.med.note),
              ]), style: const TextStyle(fontSize: 14)),
            ],
          ]),
        ),
        const SizedBox(height: 20),
      ],
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('Export Excel'),
          DateRangePicker(from: f, to: t, onFrom: (v) => setState(() => from = v), onTo: (v) => setState(() => to = v)),
          const SizedBox(height: 16),
          FilledButton(onPressed: f.compareTo(t) > 0 ? null : () => _export(s, f, t), child: const Text('Export Excel')),
          const SizedBox(height: 8),
          const Text('ไฟล์เปิดได้ด้วย Excel (ต้นแบบนี้ส่งออกเป็น .csv)', style: TextStyle(fontSize: 14)),
        ]),
      ),
    ]);
  }

  Widget _kv(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: stone600)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
      ]);
}
