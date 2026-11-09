import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase; // `show`: supabase also exports an AuthState

import 'app.dart';
import 'config.dart';
import 'lifecycle_reloader.dart';
import 'logic/auth_validators.dart';
import 'services/log_outbox.dart';
import 'services/med_sync.dart';
import 'services/notification_service.dart';
import 'services/storage.dart';
import 'services/supabase_med_repository.dart';
import 'services/supabase_auth_repository.dart';
import 'state/app_state.dart';
import 'state/auth_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('ยังไม่ได้ตั้งค่า backend (Supabase) — ดู lib/config.dart')))));
    return;
  }
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  final prefs = await SharedPreferences.getInstance();
  final service = NotificationService();
  final medRepo = SupabaseMedRepository(Supabase.instance.client);
  final outbox = LogOutbox(prefs, medRepo);
  final state = AppState(Storage(prefs), service, outbox: outbox);
  final auth = AuthState(
    SupabaseAuthRepository(Supabase.instance.client),
    prefs,
    // A fresh sign-in fills the local name/phone; signing out (or another person logging in) wipes local data.
    onSignedIn: (p, phone) {
      state.setPatient(p.nickname);
      state.setVerifiedPhone(displayPhone(phone));
    },
    // Sign-out: try to send the last records first, then drop the queue so the next user never inherits it.
    beforeSignOut: outbox.flush,
    onSignedOut: () {
      outbox.clear(); // synchronous in memory, so nothing of the old user is left when resetAll starts
      state.resetAll();
    },
  );
  await auth.init();
  // pull() flushes the outbox first (beforePull), so startup, resume and the 5-minute timer all retry unsent records.
  final medSync = MedSync(medRepo, state, canPull: () => auth.status == AuthStatus.ready, beforePull: outbox.flush);

  // Reminders (and the notification permission prompt) only exist while a user is signed in.
  var notificationsStarted = false;
  void syncReminders() {
    final ready = auth.status == AuthStatus.ready;
    state.setRemindersEnabled(ready);
    if (ready && !notificationsStarted) {
      notificationsStarted = true;
      _startNotifications(service, state);
    }
    if (ready) {
      medSync.pull();
      medSync.start();
    } else {
      medSync.stop();
    }
  }

  auth.addListener(syncReminders);
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider.value(value: auth),
      Provider<NotificationPermissions>.value(value: service),
      Provider<MedSync>.value(value: medSync),
      Provider<LogOutbox>.value(value: outbox),
    ],
    child: const LifecycleReloader(child: CareDoseApp()),
  ));
  syncReminders(); // after runApp so the UI shows before any permission dialog
}

Future<void> _startNotifications(NotificationService service, AppState state) async {
  try {
    await service.init(onAction: state.applyNotificationAction);
    await service.requestPermissions();
    await state.reload();
    await state.rescheduleNow();
  } catch (e) {
    debugPrint('notification setup failed: $e');
  }
}
