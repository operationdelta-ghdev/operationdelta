import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../models/event.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  // Channel constants — must be consistent between channel creation and scheduling
  static const String _channelId = 'ingress_event_channel';
  static const String _channelName = 'Ingress Event Alerts';
  static const String _channelDesc = 'Alerts for Ingress gameplay anomalies and modifiers';

  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  // Tracks whether init has been completed successfully
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await _initImpl();
    _initialized = true;
  }

  Future<void> _initImpl() async {
    // 1. Initialize Timezones
    tz_data.initializeTimeZones();
    try {
      final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(currentTimeZone));
      debugPrint('Timezone set to: $currentTimeZone');
    } catch (e) {
      debugPrint('Warning setting local timezone: $e. Falling back to UTC.');
      tz.setLocalLocation(tz.UTC);
    }

    // 2. Initialize Notifications plugin
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
        debugPrint('Notification tapped: ${details.payload}');
      },
    );

    // 3. Android-specific setup
    final androidImpl = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidImpl != null) {
      // CRITICAL: Explicitly create the notification channel.
      // Without this, notifications are silently dropped on Android 8+.
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await androidImpl.createNotificationChannel(channel);
      debugPrint('Notification channel created: $_channelId');

      // Request POST_NOTIFICATIONS permission (Android 13+)
      final bool? notifGranted = await androidImpl.requestNotificationsPermission();
      debugPrint('Notification permission granted: $notifGranted');
      if (notifGranted == false) {
        debugPrint('WARNING: User denied notification permission. Notifications will not appear.');
      }

      // With USE_EXACT_ALARM declared in the manifest, exact alarms are auto-granted
      // at install time. We just verify and log — no runtime prompt needed.
      try {
        final bool? canExact = await androidImpl.canScheduleExactNotifications();
        debugPrint('Can schedule exact notifications: $canExact');
        if (canExact == false) {
          debugPrint('WARNING: Exact alarm scheduling unavailable. '
              'Notifications will use inexact delivery.');
        }
      } catch (e) {
        debugPrint('canScheduleExactNotifications unavailable (pre-Android 12): $e');
      }
    }
  }

  // Resets and schedules alerts for all active and upcoming events
  Future<void> rescheduleAlarms(List<Article> articles) async {
    // Ensure plugin is initialized before scheduling
    if (!_initialized) await init();
    
    // Cancel all previously scheduled alarms first to prevent duplicates
    await _notificationsPlugin.cancelAll();
    debugPrint("Cancelled all old notifications. Scheduling fresh alarms for ${articles.length} articles...");

    if (articles.isEmpty) {
      debugPrint("No articles provided. Alarms cleared.");
      return;
    }

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
      _channelId,  // must match the channel created in init()
      _channelName,
      channelDescription: _channelDesc,
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
      debugPrint("Scheduled exact notification '$title' for $scheduledTime");
    } catch (e) {
      debugPrint("Security or other error scheduling exact notification: $e. Falling back to inexact scheduling...");
      try {
        await _notificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          scheduledTime,
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );
        debugPrint("Scheduled inexact notification '$title' for $scheduledTime");
      } catch (ex) {
        debugPrint("Error scheduling fallback notification: $ex");
      }
    }
  }

  // Converts standard local DateTime to timezone's TZDateTime using milliseconds since epoch for exact alignment
  tz.TZDateTime _toTZDateTime(DateTime dateTime) {
    return tz.TZDateTime.fromMillisecondsSinceEpoch(
      tz.local,
      dateTime.millisecondsSinceEpoch,
    );
  }
}
