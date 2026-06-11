import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../models/event.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // 1. Initialize Timezones
    tz.initializeTimeZones();
    try {
      final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(currentTimeZone));
    } catch (e) {
      debugPrint("Warning setting local timezone: $e. Falling back to UTC.");
      tz.setLocalLocation(tz.UTC);
    }

    // 2. Initialize Notifications Settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

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

    // Request permissions for Android 13+
    final androidImplementation = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }
  }

  // Resets and schedules alerts for all active and upcoming events
  Future<void> rescheduleAlarms(List<Article> articles) async {
    // Cancel all previously scheduled alarms first to prevent duplicates
    await _notificationsPlugin.cancelAll();
    debugPrint("Cancelled all old notifications. Scheduling fresh alarms...");

    final DateTime now = DateTime.now();
    int notificationId = 100; // unique incremental counter

    for (var article in articles) {
      for (var event in eventList(article)) {
        // Schedule Start notification
        final DateTime startLocal = event.getAdjustedStart(now);
        if (startLocal.isAfter(now)) {
          final tz.TZDateTime tzStart = _toTZDateTime(startLocal);
          await _scheduleNotification(
            id: notificationId++,
            title: "Ingress Event Starting: ${event.name}",
            body: "Active mutation: ${event.changes.isNotEmpty ? event.changes[0] : 'Gameplay mechanics updated.'}",
            scheduledTime: tzStart,
            payload: event.name,
          );
        }

        // Schedule End notification
        final DateTime endLocal = event.getAdjustedEnd(now);
        if (endLocal.isAfter(now)) {
          final tz.TZDateTime tzEnd = _toTZDateTime(endLocal);
          await _scheduleNotification(
            id: notificationId++,
            title: "Ingress Event Ending: ${event.name}",
            body: " gameplay changes are reverting back to default. Stand down.",
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
