import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';
import '../state/app_state.dart';
import 'notification_actions.dart';
import 'notification_plan.dart';
import 'storage.dart';

const _channelId = 'dose_reminders';
const _iosCategory = 'dose';

/// Notification buttons in display order: (actionId, Thai label).
List<(String, String)> doseActions() => const [
      ('taken', 'ทานแล้ว'),
      ('notyet', 'ยังไม่ทาน'),
      ('skip', 'ข้ามยา'),
    ];

/// Runs in a background isolate when a button is pressed and the app UI is not shown.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse r) async {
  final key = r.payload;
  final action = r.actionId;
  if (key == null || action == null || action.isEmpty) return;
  DartPluginRegistrant.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final storage = Storage(prefs);
  final now = DateTime.now();
  final res = applyDoseAction(storage.load(now), storage.loadDismissed(), action, key, now);
  await storage.save(res.data);
  await storage.saveDismissed(res.dismissed);
  await FlutterLocalNotificationsPlugin().cancel(id: notificationId(key, repeat: true));
}

class NotificationService implements NotificationScheduler {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// [onAction] receives (actionId, doseKey) for buttons handled in the main isolate.
  Future<void> init({void Function(String actionId, String key)? onAction}) async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      debugPrint('timezone lookup failed, using UTC: $e');
    }
    final category = DarwinNotificationCategory(
      _iosCategory,
      actions: [for (final (id, label) in doseActions()) DarwinNotificationAction.plain(id, label)],
    );
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [category],
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final key = r.payload;
        final action = r.actionId;
        if (key != null && action != null && action.isNotEmpty) onAction?.call(action, key);
      },
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  Future<bool> requestPermissions() async {
    final a = _android;
    if (a != null) {
      final ok = await a.requestNotificationsPermission() ?? false;
      await a.requestExactAlarmsPermission();
      return ok;
    }
    return await _ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
  }

  Future<bool> permissionsGranted() async {
    final a = _android;
    if (a != null) return await a.areNotificationsEnabled() ?? false;
    final opts = await _ios?.checkPermissions();
    return opts?.isEnabled ?? false;
  }

  NotificationDetails _details() => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'แจ้งเตือนทานยา',
          channelDescription: 'แจ้งเตือนเมื่อถึงเวลาทานยา',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          actions: [
            for (final (id, label) in doseActions())
              AndroidNotificationAction(id, label, showsUserInterface: false, cancelNotification: true),
          ],
        ),
        iOS: const DarwinNotificationDetails(categoryIdentifier: _iosCategory, presentAlert: true, presentSound: true),
      );

  @override
  Future<void> reschedule(AppData d, Set<String> dismissed, DateTime now) async {
    if (!_ready) return;
    await _plugin.cancelAll();
    final plan = planNotifications(d, dismissed, now);
    if (plan.isEmpty) return;
    final exact = await _android?.canScheduleExactNotifications() ?? true;
    final mode = exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
    final details = _details();
    for (final p in plan) {
      await _plugin.zonedSchedule(
        id: p.id,
        title: p.title,
        body: p.body,
        scheduledDate: tz.TZDateTime.from(p.at, tz.local),
        notificationDetails: details,
        androidScheduleMode: mode,
        payload: p.payload,
      );
    }
  }
}
