import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/bmi.dart';
import '../logic/thai_date.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class BmiScreen extends StatefulWidget {
  const BmiScreen({super.key});

  @override
  State<BmiScreen> createState() => _BmiScreenState();
}

class _BmiScreenState extends State<BmiScreen> {
  final w = TextEditingController();
  final h = TextEditingController();
  String err = '';

  @override
  void dispose() {
    w.dispose();
    h.dispose();
    super.dispose();
  }

  void _calc() {
    final wn = double.tryParse(w.text.trim());
    final hn = double.tryParse(h.text.trim());
    final e = validateBmiInput(wn, hn);
    setState(() => err = e ?? '');
    if (e == null) context.read<AppState>().addBmi(wn!, hn!);
  }

  @override
  Widget build(BuildContext context) {
    final bmis = context.watch<AppState>().data.bmis;
    final last = bmis.isEmpty ? null : bmis.first;
    final normal = last?.cat == 'ปกติ';
    const decimal = TextInputType.numberWithOptions(decimal: true);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('คำนวณ BMI'),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: LabeledField('น้ำหนัก (กิโลกรัม)', child: TextField(controller: w, keyboardType: decimal, decoration: const InputDecoration(hintText: 'เช่น 58')))),
            const SizedBox(width: 12),
            Expanded(child: LabeledField('ส่วนสูง (เซนติเมตร)', child: TextField(controller: h, keyboardType: decimal, decoration: const InputDecoration(hintText: 'เช่น 155')))),
          ]),
          if (err.isNotEmpty) ...[const SizedBox(height: 12), ErrorBox(err)],
          const SizedBox(height: 16),
          FilledButton(onPressed: _calc, child: const Text('คำนวณ BMI')),
        ]),
      ),
      if (last != null) ...[
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: normal ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
            border: Border.all(color: normal ? const Color(0xFF15803D) : const Color(0xFFB45309), width: 2),
            borderRadius: BorderRadius.circular(24),
          ),
          child: DefaultTextStyle(
            style: TextStyle(color: normal ? const Color(0xFF14532D) : const Color(0xFF78350F)),
            textAlign: TextAlign.center,
            child: Column(children: [
              const Text('ค่า BMI ล่าสุด', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              FittedBox(fit: BoxFit.scaleDown, child: Text(_n(last.v), style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold, height: 1.1))),
              Text(last.cat, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: stone300), borderRadius: BorderRadius.circular(16)),
        child: const Text('ผลลัพธ์เป็นข้อมูลเบื้องต้น ไม่ใช่การวินิจฉัยทางการแพทย์', style: TextStyle(fontSize: 14)),
      ),
      if (bmis.isNotEmpty) ...[
        const SizedBox(height: 20),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('ประวัติ BMI'),
            for (final b in bmis)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_n(b.v)} • ${b.cat}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('${_n(b.w)} กก. / ${_n(b.h)} ซม.', style: const TextStyle(fontSize: 14)),
                    ]),
                  ),
                  Text(
                    '${thDateShort(dateKey(DateTime.parse(b.at)))} ${thTime(DateTime.parse(b.at))}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 14),
                  ),
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }
}
