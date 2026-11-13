import 'package:flutter/material.dart';

import 'common.dart';

/// Name + phone form (relative). [fields] are (key, label); [initial] must contain an `id`.
/// [onSave] and [onDelete] return an error message to show in the form, or null when they succeeded (and closed it).
class PersonForm extends StatefulWidget {
  const PersonForm({super.key, required this.fields, required this.initial, required this.onSave, this.onDelete});
  final List<(String, String)> fields;
  final Map<String, String> initial;
  final Future<String?> Function(Map<String, String> values) onSave;
  final Future<String?> Function()? onDelete;

  @override
  State<PersonForm> createState() => _PersonFormState();
}

class _PersonFormState extends State<PersonForm> {
  late final Map<String, TextEditingController> c = {
    for (final (k, _) in widget.fields) k: TextEditingController(text: widget.initial[k] ?? ''),
  };
  String err = '';
  bool busy = false;

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      err = '';
    });
    final e = await action();
    if (mounted) {
      setState(() {
        busy = false;
        err = e ?? '';
      });
    }
  }

  void _save() => _run(() {
        final v = {for (final e in c.entries) e.key: e.value.text.trim(), 'id': widget.initial['id'] ?? ''};
        return widget.onSave(v);
      });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (k, label) in widget.fields) ...[
        LabeledField(label, child: TextField(controller: c[k], keyboardType: k == 'phone' ? TextInputType.phone : null)),
        const SizedBox(height: 16),
      ],
      if (err.isNotEmpty) ...[ErrorBox(err), const SizedBox(height: 16)],
      FilledButton(onPressed: busy ? null : _save, child: const Text('บันทึก')),
      if (widget.onDelete != null) ...[
        const SizedBox(height: 16),
        OutlinedButton(style: dangerStyle(), onPressed: busy ? null : () => _run(widget.onDelete!), child: const Text('ลบ')),
      ],
    ]);
  }
}
