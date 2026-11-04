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
  late final AppState state;
  await service.init(onAction: (action, key) => state.applyNotificationAction(action, key));
  state = AppState(Storage(await SharedPreferences.getInstance()), service);
  await service.requestPermissions();
  await service.reschedule(state.data, state.dismissed, state.now);
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      Provider<NotificationPermissions>.value(value: service),
    ],
    child: const LifecycleReloader(child: CareDoseApp()),
  ));
}
