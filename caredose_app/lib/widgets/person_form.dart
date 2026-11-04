import 'package:flutter/material.dart';

import 'common.dart';

/// Name + phone form (relative). [fields] are (key, label); [initial] must contain an `id`.
class PersonForm extends StatefulWidget {
  const PersonForm({super.key, required this.fields, required this.initial, required this.onSave, this.onDelete});
  final List<(String, String)> fields;
  final Map<String, String> initial;
  final ValueChanged<Map<String, String>> onSave;
  final VoidCallback? onDelete;

  @override
  State<PersonForm> createState() => _PersonFormState();
}

class _PersonFormState extends State<PersonForm> {
  late final Map<String, TextEditingController> c = {
    for (final (k, _) in widget.fields) k: TextEditingController(text: widget.initial[k] ?? ''),
  };
  String err = '';

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  void _save() {
    final v = {for (final e in c.entries) e.key: e.value.text.trim(), 'id': widget.initial['id'] ?? ''};
    if ((v['name'] ?? '').isEmpty || (v['phone'] ?? '').isEmpty) {
      setState(() => err = 'กรุณากรอกชื่อและเบอร์โทร');
      return;
    }
    widget.onSave(v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (k, label) in widget.fields) ...[
        LabeledField(label, child: TextField(controller: c[k], keyboardType: k == 'phone' ? TextInputType.phone : null)),
        const SizedBox(height: 16),
      ],
      if (err.isNotEmpty) ...[ErrorBox(err), const SizedBox(height: 16)],
      FilledButton(onPressed: _save, child: const Text('บันทึก')),
      if (widget.onDelete != null) ...[
        const SizedBox(height: 16),
        OutlinedButton(style: dangerStyle(), onPressed: widget.onDelete, child: const Text('ลบ')),
      ],
    ]);
  }
}
