import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/login_screen.dart';
import 'screens/not_registered_screen.dart';
import 'screens/otp_screen.dart';
import 'screens/profile_screen.dart';
import 'state/auth_state.dart';

/// Shows the login flow, the profile form or [child] (the app) depending on [AuthState].
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.child});
  final Widget child;

  Widget _page(Widget body) => Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(child: body))));

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    switch (auth.status) {
      case AuthStatus.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.unavailable:
        return _page(Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('เชื่อมต่อไม่ได้ กรุณาลองใหม่', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            FilledButton(onPressed: auth.init, child: const Text('ลองใหม่')),
            // Without this a persistent server error (e.g. a missing RPC) leaves no way back to the login screen.
            TextButton(onPressed: auth.signOut, child: const Text('ออกจากระบบ')),
          ]),
        ));
      case AuthStatus.loggedOut:
        return _page(const _LoginFlow());
      case AuthStatus.needsProfile:
        return _page(const ProfileScreen());
      case AuthStatus.notRegistered:
        return _page(const NotRegisteredScreen());
      case AuthStatus.ready:
        return child;
    }
  }
}

class _LoginFlow extends StatefulWidget {
  const _LoginFlow();

  @override
  State<_LoginFlow> createState() => _LoginFlowState();
}

class _LoginFlowState extends State<_LoginFlow> {
  String? phone;

  @override
  Widget build(BuildContext context) {
    final p = phone;
    if (p == null) return LoginScreen(onCodeSent: (e164) => setState(() => phone = e164));
    return OtpScreen(phoneE164: p, onChangePhone: () => setState(() => phone = null));
  }
}
