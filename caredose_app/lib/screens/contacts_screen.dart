import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/auth_validators.dart';
import '../logic/dose_items.dart';
import '../logic/thai_date.dart';
import '../models/models.dart';
import '../services/auth_repository.dart';
import '../services/relative_sync.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/person_form.dart';

class _ApptStyle {
  final String label;
  final Color bg, fg, border;
  const _ApptStyle(this.label, this.bg, this.fg, this.border);
}

const _apptStyles = {
  'pending': _ApptStyle('รอนัด', Color(0xFFFEF3C7), Color(0xFF78350F), Color(0xFFB45309)),
  'confirmed': _ApptStyle('ยืนยันแล้ว', Color(0xFFDCFCE7), Color(0xFF14532D), Color(0xFF15803D)),
  'rescheduled': _ApptStyle('เลื่อนนัด', Color(0xFFFFEDD5), Color(0xFF7C2D12), Color(0xFFC2410C)),
  'cancelled': _ApptStyle('ยกเลิก', Color(0xFFFEE2E2), Color(0xFF7F1D1D), Color(0xFFB91C1C)),
};

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  void _openRelative(BuildContext context, Relative? r) {
    final sync = context.read<RelativeSync>();
    showAppSheet<void>(
      context,
      title: r == null ? 'เพิ่มญาติ' : 'แก้ไขญาติ',
      builder: (ctx) => PersonForm(
        fields: const [('name', 'ชื่อ'), ('rel', 'ความสัมพันธ์'), ('phone', 'เบอร์โทร')],
        initial: r == null ? {'id': '', 'name': '', 'rel': '', 'phone': ''} : {'id': r.id, 'name': r.name, 'rel': r.rel, 'phone': r.phone},
        // Needs the network: the form stays open with the reason when the server says no.
        onSave: (v) async {
          final bad = validateRelative(name: v['name']!, rel: v['rel']!, phone: v['phone']!);
          if (bad != null) return bad;
          try {
            await sync.save(id: r?.id, name: v['name']!, rel: v['rel']!, phone: v['phone']!);
          } on AuthFailure catch (f) {
            return f.message;
          }
          if (ctx.mounted) Navigator.pop(ctx);
          return null;
        },
        onDelete: r == null
            ? null
            : () async {
                if (!await confirmDelete(ctx, r.name)) return null;
                try {
                  await sync.delete(r.id);
                } on AuthFailure catch (f) {
                  return f.message;
                }
                if (ctx.mounted) Navigator.pop(ctx);
                return null;
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data;
    final items = itemsFor(d, todayKey(s.now), s.now);
    final done = items.where((i) => i.status == DoseStatus.taken).length;
    final appts = [...d.appts]..sort((a, b) => a.at.compareTo(b.at));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ผู้ป่วย', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          Text(d.patient, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: tealTint, borderRadius: BorderRadius.circular(12)),
            child: Text('วันนี้ ทานแล้ว $done จาก ${items.length} รายการ', style: const TextStyle(fontWeight: FontWeight.w600, color: brandDark)),
          ),
        ]),
      ),
      const SizedBox(height: 20),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: SectionTitle('ญาติฉุกเฉิน')),
            OutlinedButton(onPressed: () => _openRelative(context, null), child: const Text('+ เพิ่มญาติ')),
          ]),
          for (final r in d.relatives)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE7E5E4), width: 2), borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(r.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(r.rel, style: const TextStyle(color: stone600)),
                const SizedBox(height: 4),
                Text(r.phone, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: FilledButton(onPressed: () => callNumber(context, r.phone), child: const Text('โทรหาญาติ'))),
                  // a relative an Admin added is not the patient's to change
                  if (r.editable) ...[
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton(onPressed: () => _openRelative(context, r), child: const Text('แก้ไข'))),
                  ],
                ]),
              ]),
            ),
          if (d.relatives.isEmpty) const Text('ยังไม่มีรายชื่อญาติ'),
        ]),
      ),
      const SizedBox(height: 20),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('นัดหมายแพทย์'),
          const Text('นัดหมายกำหนดโดยแพทย์หรือเจ้าหน้าที่', style: TextStyle(fontSize: 14, color: stone600)),
          const SizedBox(height: 16),
          for (final a in appts) _apptCard(a, s.now),
          if (appts.isEmpty) const Text('ยังไม่มีนัดหมาย'),
        ]),
      ),
    ]);
  }

  Widget _apptCard(Appt a, DateTime now) {
    final at = DateTime.parse(a.at);
    final past = at.isBefore(now);
    final status = a.status ?? 'pending';
    final st = _apptStyles[status] ?? _apptStyles['pending']!;
    final cancelled = status == 'cancelled';
    final rescheduled = status == 'rescheduled';
    final bg = cancelled ? const Color(0xFFFEF2F2) : (past ? const Color(0xFFF5F5F4) : tealTint);
    final border = cancelled ? const Color(0xFFEF4444) : (past ? stone300 : brand);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border, width: 2), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('สถานะนัดหมาย', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: stone600))),
          Pill(st.label, bg: st.bg, fg: st.fg, border: st.border),
        ]),
        if (past && !cancelled) const Padding(padding: EdgeInsets.only(top: 8), child: Text('นัดนี้ผ่านมาแล้ว', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: stone600))),
        if (rescheduled && a.previousAt != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF7ED), border: Border.all(color: const Color(0xFFFDBA74)), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('กำหนดเดิม', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF431407))),
              Text(
                '${thDate(dateKey(DateTime.parse(a.previousAt!)))} ${thTime(DateTime.parse(a.previousAt!))} น.',
                style: const TextStyle(decoration: TextDecoration.lineThrough, color: Color(0xFF431407)),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        Text(thDate(dateKey(at)), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, height: 1.3)),
        Text('${thTime(at)} น.', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: cancelled ? const Color(0xFF991B1B) : brand)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [const TextSpan(text: 'สถานที่: ', style: TextStyle(fontWeight: FontWeight.w600)), TextSpan(text: a.place)])),
            const SizedBox(height: 4),
            Text.rich(TextSpan(children: [const TextSpan(text: 'แผนก: ', style: TextStyle(fontWeight: FontWeight.w600)), TextSpan(text: a.dept.isEmpty ? 'ไม่ระบุ' : a.dept)])),
            if (a.note.isNotEmpty) ...[
              const Divider(height: 16),
              Text.rich(TextSpan(children: [const TextSpan(text: 'หมายเหตุ: ', style: TextStyle(fontWeight: FontWeight.w600)), TextSpan(text: a.note)])),
            ],
          ]),
        ),
        if (rescheduled || cancelled)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cancelled ? const Color(0xFFFEE2E2) : const Color(0xFFFFEDD5), borderRadius: BorderRadius.circular(12)),
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'รายละเอียดล่าสุด: ', style: TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(
                text: a.statusNote ?? (cancelled ? 'นัดหมายนี้ถูกยกเลิกโดยแพทย์หรือเจ้าหน้าที่' : 'วันและเวลานัดด้านบนเป็นกำหนดล่าสุด'),
              ),
            ])),
          ),
      ]),
    );
  }
}
