import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/thai_date.dart';
import '../models/notice.dart';
import '../services/notice_sync.dart';
import '../widgets/common.dart';

/// The latest admin messages, newest first. Read-only: there is no reply.
class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  late final Future<List<Notice>> _notices = context.read<NoticeSync>().loadRecent();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ข้อความจากผู้ดูแล')),
        body: FutureBuilder<List<Notice>>(
          future: _notices,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final list = snap.data ?? const <Notice>[];
            if (list.isEmpty) return const Center(child: Text('ยังไม่มีข้อความจากผู้ดูแล', style: TextStyle(fontSize: 18, color: stone600)));
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final n = list[i];
                final t = n.createdAt.toLocal();
                return AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(n.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(n.body, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('${thDateShort(dateKey(t))} ${thTime(t)} น.', style: const TextStyle(fontSize: 14, color: stone600)),
                  ]),
                );
              },
            );
          },
        ),
      );
}
