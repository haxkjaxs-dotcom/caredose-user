import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../logic/auth_validators.dart';
import '../services/auth_repository.dart';
import '../state/auth_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Step 2 of login: the 6-digit code. Success changes [AuthState], which swaps the screen.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.phoneE164, required this.onChangePhone});
  final String phoneE164;
  final VoidCallback onChangePhone;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const _cooldown = 60;
  final code = TextEditingController();
  String err = '';
  bool busy = false;
  int seconds = _cooldown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    seconds = _cooldown;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => seconds--);
      if (seconds <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    if (busy) return;
    if (code.text.length != 6) {
      setState(() => err = 'กรุณากรอกรหัส OTP 6 หลัก');
      return;
    }
    final auth = context.read<AuthState>();
    setState(() {
      busy = true;
      err = '';
    });
    try {
      await auth.verifyOtp(widget.phoneE164, code.text);
    } on AuthFailure catch (f) {
      if (mounted) setState(() => err = f.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _resend() async {
    if (busy || seconds > 0) return;
    final auth = context.read<AuthState>();
    setState(() {
      busy = true;
      err = '';
    });
    try {
      await auth.sendOtp(widget.phoneE164);
      if (mounted) _startCooldown();
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
          const SectionTitle('ยืนยันเบอร์โทร'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: tealTint, borderRadius: BorderRadius.circular(12)),
            child: Text('ส่งรหัส OTP ไปยัง ${displayPhone(widget.phoneE164)} แล้ว',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: brandDark)),
          ),
          const SizedBox(height: 16),
          LabeledField(
            'รหัส OTP 6 หลัก',
            child: TextField(
              key: const ValueKey('otp'),
              controller: code,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 21, letterSpacing: 4),
              decoration: const InputDecoration(hintText: '000000', counterText: ''),
              onChanged: (_) => setState(() => err = ''),
            ),
          ),
          if (err.isNotEmpty) ...[const SizedBox(height: 12), ErrorBox(err)],
          const SizedBox(height: 16),
          FilledButton(onPressed: busy ? null : _verify, child: const Text('ยืนยัน')),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy || seconds > 0 ? null : _resend,
            child: Text(seconds > 0 ? 'ส่งรหัสอีกครั้งใน $seconds วินาที' : 'ส่งรหัสอีกครั้ง'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: widget.onChangePhone, child: const Text('เปลี่ยนเบอร์')),
        ]),
      ),
    );
  }
}
