import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/auth_validators.dart';
import '../services/auth_repository.dart';
import '../state/auth_state.dart';
import '../widgets/common.dart';

/// Step 1 of login: phone number, then an OTP is sent to it.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onCodeSent});

  /// Called with the E.164 number once the code has been sent.
  final ValueChanged<String> onCodeSent;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final phone = TextEditingController();
  String err = '';
  bool busy = false;

  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy) return;
    final e164 = normalizeThaiMobile(phone.text);
    if (e164 == null) {
      setState(() => err = 'กรุณากรอกเบอร์มือถือ 10 หลักให้ถูกต้อง');
      return;
    }
    final auth = context.read<AuthState>();
    setState(() {
      busy = true;
      err = '';
    });
    try {
      await auth.sendOtp(e164);
      if (mounted) widget.onCodeSent(e164);
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
          const SectionTitle('เข้าสู่ระบบ'),
          const Text('กรอกเบอร์มือถือเพื่อรับรหัส OTP ยืนยันตัวตน', style: TextStyle(fontSize: 14, color: stone600)),
          const SizedBox(height: 16),
          LabeledField(
            'เบอร์มือถือ',
            child: TextField(
              key: const ValueKey('phone'),
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: 'เช่น 0812345678'),
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (err.isNotEmpty) ...[const SizedBox(height: 12), ErrorBox(err)],
          const SizedBox(height: 16),
          FilledButton(onPressed: busy ? null : _submit, child: const Text('ส่งรหัส OTP')),
        ]),
      ),
    );
  }
}
