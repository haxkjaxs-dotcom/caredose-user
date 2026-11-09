import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';
import '../widgets/common.dart';

/// Signed in, but no patient with this phone has been registered by an admin (or the phone is duplicated).
class NotRegisteredScreen extends StatelessWidget {
  const NotRegisteredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('ยังไม่พร้อมใช้งาน'),
          Text(auth.notice ?? 'ยังไม่พบเบอร์นี้ในระบบ กรุณาติดต่อผู้ดูแล', style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 16),
          FilledButton(onPressed: auth.retry, child: const Text('ลองใหม่')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: auth.signOut, child: const Text('ออกจากระบบ')),
        ]),
      ),
    );
  }
}
