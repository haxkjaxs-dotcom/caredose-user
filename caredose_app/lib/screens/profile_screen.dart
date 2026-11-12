import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../logic/auth_validators.dart';
import '../models/profile.dart';
import '../services/auth_repository.dart';
import '../state/auth_state.dart';
import '../widgets/common.dart';

/// Onboarding form shown once after the first login.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final nickname = TextEditingController();
  final fullName = TextEditingController();
  final age = TextEditingController();
  final other = TextEditingController();
  final selected = <String>{};
  bool none = false, consent = false, busy = false;
  String err = '';

  @override
  void dispose() {
    for (final c in [nickname, fullName, age, other]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _conditions {
    if (none) return [noConditions];
    final chips = commonConditions.where(selected.contains);
    return {...chips, ...parseConditions(other.text)}.toList();
  }

  void _toggleCondition(String label, bool on) {
    setState(() {
      none = false;
      on ? selected.add(label) : selected.remove(label);
    });
  }

  void _toggleNone(bool on) {
    setState(() {
      none = on;
      if (on) {
        selected.clear();
        other.clear();
      }
    });
  }

  Future<void> _save() async {
    if (busy) return;
    final e = validateProfile(
      nickname: nickname.text,
      fullName: fullName.text,
      ageText: age.text,
      conditions: _conditions,
      consent: consent,
    );
    if (e != null) {
      setState(() => err = e);
      return;
    }
    final auth = context.read<AuthState>();
    setState(() {
      busy = true;
      err = '';
    });
    try {
      await auth.saveProfile(Profile(
        nickname: nickname.text.trim(),
        fullName: fullName.text.trim(),
        age: int.parse(age.text.trim()),
        conditions: _conditions,
        consentAt: DateTime.now(),
      ));
    } on AuthFailure catch (f) {
      if (mounted) setState(() => err = f.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('ข้อมูลส่วนตัว'),
          LabeledField('ชื่อเล่น', child: TextField(key: const ValueKey('nickname'), controller: nickname, textInputAction: TextInputAction.next)),
          const SizedBox(height: 16),
          LabeledField('ชื่อ-นามสกุลจริง', child: TextField(key: const ValueKey('full-name'), controller: fullName, textInputAction: TextInputAction.next)),
          const SizedBox(height: 16),
          LabeledField(
            'อายุ (ปี)',
            child: TextField(
              key: const ValueKey('age'),
              controller: age,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
          const SizedBox(height: 16),
          const Text('โรคประจำตัว', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in commonConditions)
              FilterChip(label: Text(c), selected: selected.contains(c), onSelected: (on) => _toggleCondition(c, on)),
            FilterChip(label: const Text(noConditions), selected: none, onSelected: _toggleNone),
          ]),
          const SizedBox(height: 12),
          LabeledField(
            'โรคอื่น ๆ (หากไม่มีไม่ต้องใส่)',
            child: TextField(
              key: const ValueKey('other-conditions'),
              controller: other,
              decoration: const InputDecoration(hintText: 'หลายโรคให้คั่นด้วยเครื่องหมายจุลภาค'),
              onChanged: (v) {
                if (v.trim().isNotEmpty && none) setState(() => none = false);
              },
            ),
          ),
          const SizedBox(height: 8),
          // Own Material: AppCard has a background colour that would hide the tile's ink (Flutter asserts).
          Material(
            color: Colors.transparent,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: consent,
              onChanged: (v) => setState(() => consent = v ?? false),
              title: const Text('ยินยอมให้เก็บข้อมูลสุขภาพของฉันไว้ในระบบ'),
            ),
          ),
          if (err.isNotEmpty) ...[const SizedBox(height: 8), ErrorBox(err)],
          const SizedBox(height: 16),
          FilledButton(onPressed: consent && !busy ? _save : null, child: const Text('บันทึก')),
        ]),
      ),
    );
  }
}
