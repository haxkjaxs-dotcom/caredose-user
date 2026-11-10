import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';
import '../state/app_state.dart';
import 'notice_repository.dart';
import 'notification_plan.dart';
import 'storage.dart';

const _channelId = 'dose_reminders';
const _adminChannelId = 'admin_messages';
const _iosCategory = 'dose';

/// Notification buttons in display order: (actionId, Thai label).
List<(String, String)> doseActions() => const [
      ('taken', 'ทานแล้ว'),
      ('notyet', 'ยังไม่ทาน'),
      ('skip', 'ยังไม่ได้ทาน'),
    ];

/// Runs in a background isolate when a button is pressed and the app UI is not shown.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse r) async {
  final key = r.payload;
  final action = r.actionId;
  if (key == null || action == null || action.isEmpty) return;
  DartPluginRegistrant.ensureInitialized();
  // Queue only: AppState is the single writer of the main data and applies this on its next save/reload.
  final storage = Storage(await SharedPreferences.getInstance());
  await storage.appendPending('$action\t$key\t${DateTime.now().toIso8601String()}');
  await FlutterLocalNotificationsPlugin().cancel(id: notificationId(key, repeat: true));
}

class NotificationService implements NotificationScheduler, NotificationPermissions, NoticeDisplay {
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

  @override
  Future<bool> requestPermissions() async {
    final a = _android;
    if (a != null) {
      final ok = await a.requestNotificationsPermission() ?? false;
      await a.requestExactAlarmsPermission();
      return ok;
    }
    return await _ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
  }

  @override
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

  /// An admin message, shown right away (no dose buttons).
  @override
  Future<bool> show(int id, String title, String body) async {
    if (!_ready) return false;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _adminChannelId,
          'ข้อความจากผู้ดูแล',
          channelDescription: 'ข้อความที่ผู้ดูแลส่งถึงคุณ',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
    return true;
  }

  /// Drops every scheduled reminder and every dose reminder already in the tray, but leaves admin messages there:
  /// cancelAll() would also wipe a message the patient has not looked at yet each time a dose is recorded.
  Future<void> _cancelDoseNotifications() async {
    try {
      await _plugin.cancelAllPendingNotifications();
      for (final n in await _plugin.getActiveNotifications()) {
        final id = n.id;
        if (id != null && n.channelId != _adminChannelId) await _plugin.cancel(id: id);
      }
    } catch (e) {
      debugPrint('selective cancel failed, cancelling everything: $e');
      await _plugin.cancelAll();
    }
  }

  @override
  Future<void> reschedule(AppData d, Set<String> dismissed, DateTime now) async {
    if (!_ready) return;
    await _cancelDoseNotifications();
    // zonedSchedule throws for a date already past, so keep a small lead over "now".
    final plan = planNotifications(d, dismissed, now.add(const Duration(seconds: 5)));
    if (plan.isEmpty) return;
    final exact = await _android?.canScheduleExactNotifications() ?? true;
    final mode = exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
    final details = _details();
    for (final p in plan) {
      try {
        await _plugin.zonedSchedule(
          id: p.id,
          title: p.title,
          body: p.body,
          scheduledDate: tz.TZDateTime.from(p.at, tz.local),
          notificationDetails: details,
          androidScheduleMode: mode,
          payload: p.payload,
        );
      } catch (e) {
        // One rejected entry must not drop the rest of the schedule.
        debugPrint('schedule ${p.payload} failed: $e');
      }
    }
  }
}
