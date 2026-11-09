import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'services/med_sync.dart';
import 'state/app_state.dart';

/// Re-reads storage (notification buttons may have written to it) when the app
/// returns to the foreground, refreshes the clock and pulls the server's plans.
class LifecycleReloader extends StatefulWidget {
  const LifecycleReloader({super.key, required this.child});
  final Widget child;

  @override
  State<LifecycleReloader> createState() => _LifecycleReloaderState();
}

class _LifecycleReloaderState extends State<LifecycleReloader> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    context.read<AppState>().reload();
    context.read<MedSync>().pull();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
