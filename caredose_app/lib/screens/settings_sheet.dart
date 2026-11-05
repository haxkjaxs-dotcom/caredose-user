import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Body of the settings bottom sheet (opened with `showAppSheet`).
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final TextEditingController name = TextEditingController(text: context.read<AppState>().data.patient);
  bool about = false, permissionOk = true;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final ok = await context.read<NotificationPermissions>().permissionsGranted();
    if (mounted) setState(() => permissionOk = ok);
  }

  Future<void> _requestPermission() async {
    await context.read<NotificationPermissions>().requestPermissions();
    await _checkPermission();
  }

  Future<void> _signOut() async {
    final auth = context.read<AuthState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('ออกจากระบบ? ข้อมูลยาและประวัติในเครื่องนี้จะถูกล้างด้วย'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ออกจากระบบ')),
        ],
      ),
    );
    if (ok == true) {
      await auth.signOut();
      widget.onClose();
    }
  }

  Future<void> _reset() async {
    final s = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('ลบข้อมูลทั้งหมดในเครื่อง และเริ่มใหม่ด้วยข้อมูลตัวอย่าง?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ลบ')),
        ],
      ),
    );
    if (ok == true) {
      await s.resetAll();
      widget.onClose();
    }
  }

  Widget _switchRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged, {Key? switchKey, Color? bg, Color? border}) {
    return Container(
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(color: bg, border: border == null ? null : Border.all(color: border, width: 2), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(subtitle, style: const TextStyle(fontSize: 14, color: stone600)),
          ]),
        ),
        Switch(key: switchKey, value: value, onChanged: onChanged),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data;
    const channels = [
      ('app', 'ผ่านแอป', 'แจ้งเตือนบนโทรศัพท์'),
      ('sms', 'SMS', 'ส่งข้อความไปยังเบอร์ที่ยืนยัน (ตัวอย่าง: ยังไม่ส่ง SMS จริง)'),
      ('both', 'ทั้งแอปและ SMS', 'รับทั้งสองช่องทาง (ตัวอย่าง: ส่งจริงเฉพาะผ่านแอป)'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LabeledField('ชื่อผู้ใช้', child: TextField(controller: name, onChanged: s.setPatient)),
      const SizedBox(height: 20),
      const Text('ขนาดตัวอักษร', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Row(children: [
        for (final (v, l) in const [('normal', 'ปกติ'), ('large', 'ใหญ่'), ('xl', 'ใหญ่มาก')])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: d.size == v
                  ? FilledButton(onPressed: () => s.setSize(v), child: Text(l))
                  : OutlinedButton(onPressed: () => s.setSize(v), child: Text(l)),
            ),
          ),
      ]),
      const SizedBox(height: 20),
      AppCard(
        borderColor: stone300,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('การแจ้งเตือนทานยา'),
          _switchRow('เปิดการแจ้งเตือน', d.notify ? 'เปิดอยู่' : 'ปิดอยู่ อาจทำให้ลืมทานยา', d.notify, s.setNotify,
              switchKey: const ValueKey('notify-switch'), bg: tealTint),
          if (!permissionOk) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFFBEB), border: Border.all(color: const Color(0xFFF59E0B), width: 2), borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('การแจ้งเตือนของเครื่องยังปิดอยู่', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF451A03))),
                const Text('แอปจะส่งการแจ้งเตือนทานยาไม่ได้จนกว่าจะอนุญาต', style: TextStyle(fontSize: 14, color: Color(0xFF451A03))),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _requestPermission, child: const Text('อนุญาตการแจ้งเตือน')),
              ]),
            ),
          ],
          IgnorePointer(
            ignoring: !d.notify,
            child: Opacity(
              opacity: d.notify ? 1 : 0.5,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: 20),
                const Text('รับการแจ้งเตือนผ่าน', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                for (final (v, title, detail) in channels)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => s.setChannel(v),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 64),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: d.notifyChannel == v ? tealTint : Colors.white,
                          border: Border.all(color: d.notifyChannel == v ? brand : stone300, width: 2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${d.notifyChannel == v ? '✓ ' : ''}$title', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(detail, style: const TextStyle(fontSize: 14, color: stone600)),
                        ]),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                _phoneBox(s),
                const SizedBox(height: 20),
                _switchRow('เตือนซ้ำ 1 ครั้ง', 'หลังถึงเวลาทานยา 15 นาที หากยังไม่ได้บันทึก', d.repeatReminder, s.setRepeat, border: stone300),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFF0FDF4), border: Border.all(color: const Color(0xFF15803D), width: 2), borderRadius: BorderRadius.circular(16)),
                  child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('หยุดเตือนอัตโนมัติ', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF052E16))),
                    Text('ระบบจะหยุดแจ้งเตือนรายการนั้นทันที เมื่อกด “ทานแล้ว” หรือ “ยังไม่ได้ทาน” ส่วนปุ่ม “ยังไม่ทาน” บนการแจ้งเตือนจะไม่เตือนซ้ำและรอรอบยาถัดไป',
                        style: TextStyle(fontSize: 14, color: Color(0xFF052E16))),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 20),
      OutlinedButton(style: dangerStyle(), onPressed: _reset, child: const Text('จัดการข้อมูลในเครื่อง: ล้างข้อมูล')),
      const SizedBox(height: 20),
      OutlinedButton(style: dangerStyle(), onPressed: _signOut, child: const Text('ออกจากระบบ')),
      const SizedBox(height: 20),
      OutlinedButton(onPressed: () => setState(() => about = !about), child: const Text('เกี่ยวกับแอป')),
      if (about)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text('CareDose (ยาอุ่นใจ) ข้อมูลยาและประวัติการทานยาเก็บในเครื่องนี้ ส่วนข้อมูลส่วนตัวเก็บในระบบหลังเข้าสู่ระบบด้วยเบอร์โทร', style: TextStyle(fontSize: 14)),
        ),
    ]);
  }

  Widget _phoneBox(AppState s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: stone300, width: 2), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('เบอร์รับ SMS ที่ยืนยันแล้ว', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: stone600)),
            Text(s.data.verifiedPhone, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          ]),
          const Pill('ยืนยันด้วย OTP แล้ว', bg: Color(0xFFDCFCE7), fg: Color(0xFF14532D), border: Color(0xFF15803D)),
        ]),
        const SizedBox(height: 8),
        const Text('เบอร์ที่ใช้เข้าสู่ระบบ', style: TextStyle(fontSize: 14, color: stone600)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(12)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ตัวอย่างข้อความ SMS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF451A03))),
            Text('“ถึงเวลาทานยาตามแผนแล้ว”', style: TextStyle(color: Color(0xFF451A03))),
            SizedBox(height: 4),
            Text('ข้อความจะไม่แสดงชื่อยาหรือข้อมูลสุขภาพ และ SMS อาจมีค่าใช้จ่ายตามเครือข่าย', style: TextStyle(fontSize: 14, color: Color(0xFF451A03))),
          ]),
        ),
      ]),
    );
  }
}
