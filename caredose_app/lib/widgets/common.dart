import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/dose_items.dart';
import '../theme.dart';

class StatusStyle {
  final Color bg, fg, border;
  const StatusStyle(this.bg, this.fg, this.border);
}

const _statusStyles = {
  DoseStatus.taken: StatusStyle(Color(0xFFDCFCE7), Color(0xFF14532D), Color(0xFF15803D)),
  DoseStatus.skipped: StatusStyle(Color(0xFFE7E5E4), Color(0xFF292524), Color(0xFF78716C)),
  DoseStatus.pending: StatusStyle(Color(0xFFFEF3C7), Color(0xFF78350F), Color(0xFFB45309)),
  DoseStatus.missed: StatusStyle(Color(0xFFFEE2E2), Color(0xFF7F1D1D), Color(0xFFB91C1C)),
};

StatusStyle statusStyle(DoseStatus s) => _statusStyles[s]!;

const stone600 = Color(0xFF57534E);
const stone300 = Color(0xFFD6D3D1);
const tealTint = Color(0xFFF0FDFA);

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final DoseStatus status;

  @override
  Widget build(BuildContext context) {
    final st = statusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(color: st.bg, border: Border.all(color: st.border, width: 2), borderRadius: BorderRadius.circular(99)),
      child: Text(doseStatusLabel(status), style: TextStyle(color: st.fg, fontWeight: FontWeight.bold, fontSize: 14)),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.bg, required this.fg, required this.border});
  final String text;
  final Color bg, fg, border;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border, width: 2), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 14)),
      );
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.color = Colors.white, this.borderColor = const Color(0xFFE7E5E4)});
  final Widget child;
  final Color color, borderColor;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(24), border: Border.all(color: borderColor)),
        child: child,
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)));
}

class LabeledField extends StatelessWidget {
  const LabeledField(this.label, {super.key, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          child,
        ],
      );
}

class ErrorBox extends StatelessWidget {
  const ErrorBox(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(12)),
          child: Text(text, style: const TextStyle(color: Color(0xFF7F1D1D), fontWeight: FontWeight.w600)),
        ),
      );
}

ButtonStyle dangerStyle() => OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF991B1B),
      side: const BorderSide(color: Color(0xFFB91C1C), width: 2),
    );

/// Bottom sheet with a title row and a close button; [builder] supplies the body.
Future<T?> showAppSheet<T>(BuildContext context, {required String title, required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: paper,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
              OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('ปิด')),
            ]),
            const SizedBox(height: 16),
            builder(ctx),
          ],
        ),
      ),
    ),
  );
}

Future<bool> confirmDelete(BuildContext context, String what) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text('ต้องการลบ "$what" ใช่หรือไม่?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ลบ')),
      ],
    ),
  );
  return r ?? false;
}

Future<void> callNumber(BuildContext context, String phone) async {
  final messenger = ScaffoldMessenger.of(context);
  bool ok = false;
  try {
    ok = await launchUrl(Uri(scheme: 'tel', path: phone));
  } catch (_) {}
  if (!ok) messenger.showSnackBar(const SnackBar(content: Text('โทรไม่ได้')));
}
