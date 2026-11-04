import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/bmi_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_sheet.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'widgets/common.dart';

class CareDoseApp extends StatelessWidget {
  const CareDoseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final size = context.select<AppState, String>((s) => s.data.size);
    return MaterialApp(
      title: 'CareDose',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScaleFor(size))),
        child: child!,
      ),
      home: const _Shell(),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int tab = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Refresh the clock and pick up notification-button changes written in the background.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      final s = context.read<AppState>();
      s.tick();
      s.reload();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _body() {
    switch (tab) {
      case 0:
        return const HomeScreen();
      case 1:
        return const BmiScreen();
      case 2:
        return const HistoryScreen();
      default:
        return const ContactsScreen();
    }
  }

  void _openSettings() {
    showAppSheet<void>(context, title: 'ตั้งค่า', builder: (ctx) => SettingsSheet(onClose: () => Navigator.pop(ctx)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        toolbarHeight: 72,
        titleSpacing: 20,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CareDose', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, height: 1.1)),
          Text('ยาอุ่นใจ', style: TextStyle(fontSize: 14)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white24, minimumSize: const Size(0, 48)),
              onPressed: _openSettings,
              icon: const Icon(Icons.menu),
              label: const Text('ตั้งค่า'),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 576),
          child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: _body()),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        height: 72,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFCCFBF1),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'หน้าหลัก'),
          NavigationDestination(icon: Icon(Icons.monitor_weight_outlined), selectedIcon: Icon(Icons.monitor_weight), label: 'BMI'),
          NavigationDestination(icon: Icon(Icons.history), label: 'ประวัติ'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'ญาติ/นัด'),
        ],
      ),
    );
  }
}
