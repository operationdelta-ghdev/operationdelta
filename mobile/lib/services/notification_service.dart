import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../models/event.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // 1. Initialize Timezones
    tz_data.initializeTimeZones();
    try {
      final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(currentTimeZone));
    } catch (e) {
      debugPrint("Warning setting local timezone: $e. Falling back to UTC.");
      tz.setLocalLocation(tz.UTC);
    }

    // 2. Initialize Notifications Settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('launcher_icon');

    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        debugPrint("Notification clicked: ${details.payload}");
      },
    );

    // Request permissions for Android 13+ and exact alarms permission for Android 12+
    final androidImplementation = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
      try {
        await androidImplementation.requestExactAlarmsPermission();
      } catch (e) {
        debugPrint("Error requesting exact alarms permission: $e");
      }
    }
  }

  // Resets and schedules alerts for all active and upcoming events
  Future<void> rescheduleAlarms(List<Article> articles) async {
    // Cancel all previously scheduled alarms first to prevent duplicates
    await _notificationsPlugin.cancelAll();
    debugPrint("Cancelled all old notifications. Scheduling fresh alarms...");

    // Load preferences
    final prefs = await SharedPreferences.getInstance();
    final bool notifyStart = prefs.getBool('notify_event_start') ?? true;
    final bool notifyOneDayStart = prefs.getBool('notify_one_day_start') ?? true;
    final bool notifyOneDayEnd = prefs.getBool('notify_one_day_end') ?? true;
    final bool notifyEnd = prefs.getBool('notify_event_end') ?? true;

    debugPrint("Notification preferences -> Start: $notifyStart, 1DayStart: $notifyOneDayStart, 1DayEnd: $notifyOneDayEnd, End: $notifyEnd");

    final DateTime now = DateTime.now();
    int notificationId = 100; // unique incremental counter

    for (var article in articles) {
      for (var event in eventList(article)) {
        final DateTime startLocal = event.getAdjustedStart(now);
        final DateTime endLocal = event.getAdjustedEnd(now);

        // 1. Event Start notification
        if (notifyStart && startLocal.isAfter(now)) {
          final tz.TZDateTime tzStart = _toTZDateTime(startLocal);
          await _scheduleNotification(
            id: notificationId++,
            title: "Ingress Event Starting: ${event.name}",
            body: "Active mutation: ${event.changes.isNotEmpty ? event.changes[0] : 'Gameplay mechanics updated.'}",
            scheduledTime: tzStart,
            payload: event.name,
          );
        }

        // 2. 1 day notice before event start
        if (notifyOneDayStart) {
          final DateTime oneDayBeforeStart = startLocal.subtract(const Duration(days: 1));
          if (oneDayBeforeStart.isAfter(now)) {
            final tz.TZDateTime tzOneDayStart = _toTZDateTime(oneDayBeforeStart);
            await _scheduleNotification(
              id: notificationId++,
              title: "Ingress Event Notice: ${event.name} starts in 24h",
              body: "Prepare for upcoming changes: ${event.changes.isNotEmpty ? event.changes[0] : 'Gameplay mechanics.'}",
              scheduledTime: tzOneDayStart,
              payload: event.name,
            );
          }
        }

        // 3. 1 day notice before event end
        if (notifyOneDayEnd) {
          final DateTime oneDayBeforeEnd = endLocal.subtract(const Duration(days: 1));
          if (oneDayBeforeEnd.isAfter(now) && oneDayBeforeEnd.isBefore(endLocal)) {
            final tz.TZDateTime tzOneDayEnd = _toTZDateTime(oneDayBeforeEnd);
            await _scheduleNotification(
              id: notificationId++,
              title: "Ingress Event Notice: ${event.name} ends in 24h",
              body: "Make the most of the active modifiers before they revert.",
              scheduledTime: tzOneDayEnd,
              payload: event.name,
            );
          }
        }

        // 4. Event End notification
        if (notifyEnd && endLocal.isAfter(now)) {
          final tz.TZDateTime tzEnd = _toTZDateTime(endLocal);
          await _scheduleNotification(
            id: notificationId++,
            title: "Ingress Event Ending: ${event.name}",
            body: "Gameplay changes are reverting back to default. Stand down.",
            scheduledTime: tzEnd,
            payload: event.name,
          );
        }
      }
    }
    debugPrint("Finished scheduling alarms. Next ID: $notificationId");
  }

  // Helper helper to flatmap article list into individual events
  List<IngressEvent> eventList(Article article) {
    return article.events;
  }

  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledTime,
    required String payload,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'ingress_event_channel',
      'Ingress Event Alerts',
      channelDescription: 'Alerts for Ingress gameplay anomalies and modifiers',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTime,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
      debugPrint("Scheduled notification '$title' for $scheduledTime");
    } catch (e) {
      debugPrint("Error scheduling notification: $e");
    }
  }

  // Converts standard local DateTime to timezone's TZDateTime
  tz.TZDateTime _toTZDateTime(DateTime dateTime) {
    return tz.TZDateTime.from(dateTime, tz.local);
  }
}
