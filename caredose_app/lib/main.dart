import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'lifecycle_reloader.dart';
import 'services/notification_service.dart';
import 'services/storage.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final service = NotificationService();
  final state = AppState(Storage(await SharedPreferences.getInstance()), service);
  // Show the UI first; a notification setup failure must never leave a blank app.
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      Provider<NotificationPermissions>.value(value: service),
    ],
    child: const LifecycleReloader(child: CareDoseApp()),
  ));
  await _startNotifications(service, state);
}

Future<void> _startNotifications(NotificationService service, AppState state) async {
  try {
    await service.init(onAction: state.applyNotificationAction);
    await service.requestPermissions();
    await state.reload();
    await service.reschedule(state.data, state.dismissed, DateTime.now());
  } catch (e) {
    debugPrint('notification setup failed: $e');
  }
}
