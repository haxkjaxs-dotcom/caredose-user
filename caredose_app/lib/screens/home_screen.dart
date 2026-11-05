import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/dose_items.dart';
import '../logic/thai_date.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

Color _hex(String h) => Color(int.parse('FF${h.replaceFirst('#', '')}', radix: 16));

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ({List<String> keys, String time})? _bulk;
  Timer? _bulkTimer;

  @override
  void dispose() {
    _bulkTimer?.cancel();
    super.dispose();
  }

  void _setBulk(List<String> keys, String time) {
    _bulkTimer?.cancel();
    setState(() => _bulk = (keys: keys, time: time));
    _bulkTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _bulk = null);
    });
  }

  void _openDetail(Med med) {
    showAppSheet<void>(
      context,
      title: 'รายละเอียดยา',
      builder: (_) => Column(children: [
        Container(
          width: 144,
          height: 144,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _hex(med.color), borderRadius: BorderRadius.circular(24)),
          child: Text(med.name.characters.take(1).toString(), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        const SizedBox(height: 16),
        Text(med.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(med.dosage, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(med.meal.isEmpty ? 'ใช้ตามคำแนะนำของแพทย์' : med.meal),
        const SizedBox(height: 4),
        Text('เวลา ${med.times.join(', ')} น.'),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFFFFBEB), border: Border.all(color: const Color(0xFFF59E0B), width: 2), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('คำเตือนและข้อควรจำ', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF451A03))),
            const SizedBox(height: 4),
            Text(
              med.note.isEmpty ? 'ทานยาตามขนาดและเวลาที่แพทย์กำหนด หากมีอาการผิดปกติให้ติดต่อแพทย์' : med.note,
              style: const TextStyle(color: Color(0xFF451A03)),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        const Text('ข้อมูลนี้เป็นแบบอ่านอย่างเดียว หากต้องการแก้ไข กรุณาติดต่อแพทย์หรือเจ้าหน้าที่',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: stone600)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final now = s.now;
    final today = todayKey(now);
    final items = itemsFor(s.data, today, now);
    bool due(DoseItem it) => !doseTime(today, it.time).isAfter(now);
    final next = items.where((i) => i.status == DoseStatus.pending).firstOrNull ?? items.where((i) => i.status == DoseStatus.missed).firstOrNull;
    final nextGroup = next == null ? <DoseItem>[] : items.where((i) => i.time == next.time && i.status == next.status).toList();
    final times = items.map((i) => i.time).toSet().toList();
    final missed = next?.status == DoseStatus.missed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: missed ? const Color(0xFF991B1B) : brand, borderRadius: BorderRadius.circular(24)),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(missed ? 'ยาที่เลยเวลา' : 'เวลาทานยาครั้งถัดไป', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              if (next != null) ...[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('${next.time} น.', style: const TextStyle(fontSize: 52, fontWeight: FontWeight.bold, height: 1.2)),
                ),
                Text(nextGroup.map((i) => '${i.med.name} ${i.med.dosage}').join(' • '), style: const TextStyle(fontSize: 18)),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(items.isNotEmpty ? 'ทานยาครบแล้ววันนี้' : 'วันนี้ไม่มียา', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ),
              const SizedBox(height: 8),
              Text(thDate(today), style: const TextStyle(fontSize: 14)),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        const Text('ยาวันนี้', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        if (items.isEmpty) const AppCard(child: Text('ยังไม่มียาในวันนี้ แพทย์จะเป็นผู้เพิ่มยาให้')),
        for (final time in times) ...[
          _mealCard(s, items.where((i) => i.time == time).toList(), time, due),
          const SizedBox(height: 20),
        ],
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('แพทย์ผู้ดูแล'),
            for (final x in s.data.doctors)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE7E5E4)), borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(x.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(x.spec, style: const TextStyle(fontSize: 14)),
                  ])),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: () => callNumber(context, x.phone), child: const Text('โทร')),
                ]),
              ),
            if (s.data.doctors.isEmpty) const Text('ยังไม่มีรายชื่อแพทย์'),
          ]),
        ),
      ],
    );
  }

  Widget _mealCard(AppState s, List<DoseItem> meal, String time, bool Function(DoseItem) due) {
    final available = meal.where((i) => i.log == null && due(i)).toList();
    final future = meal.every((i) => !due(i));
    final allRecorded = meal.every((i) => i.log != null);
    final label = future
        ? 'ยังไม่ถึงเวลา $time น.'
        : available.isEmpty
            ? 'มื้อนี้บันทึกครบแล้ว'
            : available.length < meal.length
                ? 'ทานยาที่เหลือ (${available.length} รายการ)'
                : 'ทานครบทุกตัวในมื้อนี้ (${available.length} รายการ)';
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$time น.', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: brand)),
            Text('${meal.length} รายการในมื้อนี้', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ])),
          if (allRecorded) const Pill('บันทึกแล้ว', bg: Color(0xFFDCFCE7), fg: Color(0xFF14532D), border: Color(0xFF15803D)),
        ]),
        const Divider(height: 24, thickness: 2),
        for (final it in meal) ...[
          _doseRow(s, it),
          if (it != meal.last) const Divider(height: 24),
        ],
        const SizedBox(height: 16),
        if (_bulk?.time == time)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFDCFCE7), border: Border.all(color: const Color(0xFF15803D), width: 2), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('บันทึกยามื้อนี้แล้ว', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF052E16))),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  s.undoKeys(_bulk!.keys);
                  _bulkTimer?.cancel();
                  setState(() => _bulk = null);
                },
                child: const Text('ย้อนกลับ'),
              ),
            ]),
          )
        else
          FilledButton(
            onPressed: future || available.isEmpty
                ? null
                : () {
                    final keys = s.markMeal(meal);
                    if (keys.isNotEmpty) _setBulk(keys, time);
                  },
            child: Text(label, textAlign: TextAlign.center),
          ),
      ]),
    );
  }

  Widget _doseRow(AppState s, DoseItem it) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _hex(it.med.color), borderRadius: BorderRadius.circular(16)),
          child: Text(it.med.name.characters.take(1).toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.med.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, height: 1.2)),
            Text('${it.med.dosage}${it.med.meal.isEmpty ? '' : ' • ${it.med.meal}'}'),
            const SizedBox(height: 4),
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusBadge(it.status),
              if (it.log != null) Text('เวลา ${thTime(DateTime.parse(it.log!.at))} น.', style: const TextStyle(fontSize: 14)),
            ]),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      if (it.log != null)
        OutlinedButton(onPressed: () => s.undo(it), child: const Text('ยกเลิกการบันทึก'))
      else
        Row(children: [
          Expanded(child: FilledButton(onPressed: () => s.mark(it, DoseStatus.taken), child: const Text('ทานแล้ว'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: () => s.mark(it, DoseStatus.skipped), child: const Text('ยังไม่ได้ทาน'))),
        ]),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: () => _openDetail(it.med), child: const Text('ดูรายละเอียด')),
    ]);
  }
}
