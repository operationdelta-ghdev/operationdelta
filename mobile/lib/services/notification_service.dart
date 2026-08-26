import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../models/event.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  // Channel constants — must be consistent between channel creation and scheduling
  // Channel constants — must be consistent between channel creation and scheduling
  static const String _channelId = 'ingress_event_channel_v3';
  static const String _channelName = 'Ingress Event Alerts';
  static const String _channelDesc = 'Alerts for Ingress gameplay anomalies and modifiers';

  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  // Tracks whether init has been completed successfully
  bool _initialized = false;

  // ── Phase 1: Initialize plugin + timezone (safe before runApp) ──────────────
  Future<void> initPlugin() async {
    if (_initialized) return;
    await _initPluginImpl();
    _initialized = true;
  }

  // ── Phase 2: Request runtime permissions (must run after first frame) ────────
  Future<void> requestPermissions() async {
    final androidImpl = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl == null) return;

    // POST_NOTIFICATIONS (Android 13+) — shows a system dialog
    final bool? notifGranted = await androidImpl.requestNotificationsPermission();
    debugPrint('Notification permission granted: $notifGranted');
    if (notifGranted == false) {
      debugPrint('WARNING: User denied notification permission.');
    }

    // Exact alarms check & request
    try {
      final bool? canExact = await androidImpl.canScheduleExactNotifications();
      debugPrint('Can schedule exact notifications: $canExact');
      if (canExact == false) {
        await androidImpl.requestExactAlarmsPermission();
      }
    } catch (e) {
      debugPrint('canScheduleExactNotifications check failed: $e');
    }
  }

  // Keep backwards-compatible init() that does both phases
  Future<void> init() async {
    await initPlugin();
    await requestPermissions();
  }

  /// Fires an immediate visible notification — use to verify channel/permission setup.
  Future<String> sendTestNotification() async {
    if (!_initialized) await initPlugin();
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: 'ic_notification',
    );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );
    try {
      await _notificationsPlugin.show(
        0,
        '🔔 Test Notification',
        'If you see this, channel and permissions are working correctly.',
        details,
      );
      return 'SUCCESS: Immediate notification sent.';
    } catch (e) {
      return 'FAILED: $e';
    }
  }

  Future<void> _initPluginImpl() async {
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

    // 2. Initialize Notifications plugin with drawable resource
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('ic_notification');

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

    // 3. Create Android notification channel (required for Android 8+)
    final androidImpl = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
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
    }
  }

  // Resets and schedules alerts for all active and upcoming events
  Future<void> rescheduleAlarms(List<Article> articles) async {
    // Ensure the plugin is initialized. Only call initPlugin() here —
    // requestPermissions() is handled separately via post-frame callback
    // so we do not show a second unexpected permission dialog.
    if (!_initialized) await initPlugin();
    
    // Cancel all previously scheduled alarms first to prevent duplicates
    await _notificationsPlugin.cancelAll();
    debugPrint('Cancelled all old notifications. Scheduling alarms for ${articles.length} articles...');

    if (articles.isEmpty) {
      debugPrint('No articles provided. Alarms cleared.');
      return;
    }

    // Load preferences
    final prefs = await SharedPreferences.getInstance();
    final bool notifyStart = prefs.getBool('notify_event_start') ?? true;
    final bool notifyOneDayStart = prefs.getBool('notify_one_day_start') ?? true;
    final bool notifyOneDayEnd = prefs.getBool('notify_one_day_end') ?? true;
    final bool notifyEnd = prefs.getBool('notify_event_end') ?? true;

    debugPrint('Notification prefs → Start:$notifyStart 1DayStart:$notifyOneDayStart 1DayEnd:$notifyOneDayEnd End:$notifyEnd');

    final DateTime now = DateTime.now();
    debugPrint('Scheduling relative to now: $now (${now.timeZoneName})');
    int notificationId = 100;
    int scheduledCount = 0;

    for (var article in articles) {
      for (var event in eventList(article)) {
        final DateTime startLocal = event.getAdjustedStart(now);
        final DateTime endLocal = event.getAdjustedEnd(now);

        // 1. Event Start notification
        if (notifyStart && startLocal.isAfter(now)) {
          final tz.TZDateTime tzStart = _toTZDateTime(startLocal);
          final diffMs = startLocal.difference(now).inSeconds;
          debugPrint('→ Scheduling START for "${event.name}" at $tzStart (in ${diffMs}s)');
          await _scheduleNotification(
            id: notificationId++,
            title: "Ingress Event Starting: ${event.name}",
            body: "Active mutation: ${event.changes.isNotEmpty ? event.changes[0] : 'Gameplay mechanics updated.'}",
            scheduledTime: tzStart,
            payload: event.name,
          );
          scheduledCount++;
        } else if (notifyStart) {
          debugPrint('→ SKIPPED START for "${event.name}": startLocal=$startLocal is not after now=$now');
        }

        // 2. 1 day notice before event start
        if (notifyOneDayStart) {
          final DateTime oneDayBeforeStart = startLocal.subtract(const Duration(days: 1));
          if (oneDayBeforeStart.isAfter(now)) {
            final tz.TZDateTime tzOneDayStart = _toTZDateTime(oneDayBeforeStart);
            debugPrint('→ Scheduling 24H-BEFORE-START for "${event.name}" at $tzOneDayStart');
            await _scheduleNotification(
              id: notificationId++,
              title: "Ingress Event Notice: ${event.name} starts in 24h",
              body: "Prepare for upcoming changes: ${event.changes.isNotEmpty ? event.changes[0] : 'Gameplay mechanics.'}",
              scheduledTime: tzOneDayStart,
              payload: event.name,
            );
            scheduledCount++;
          }
        }

        // 3. 1 day notice before event end
        if (notifyOneDayEnd) {
          final DateTime oneDayBeforeEnd = endLocal.subtract(const Duration(days: 1));
          if (oneDayBeforeEnd.isAfter(now) && oneDayBeforeEnd.isBefore(endLocal)) {
            final tz.TZDateTime tzOneDayEnd = _toTZDateTime(oneDayBeforeEnd);
            debugPrint('→ Scheduling 24H-BEFORE-END for "${event.name}" at $tzOneDayEnd');
            await _scheduleNotification(
              id: notificationId++,
              title: "Ingress Event Notice: ${event.name} ends in 24h",
              body: "Make the most of the active modifiers before they revert.",
              scheduledTime: tzOneDayEnd,
              payload: event.name,
            );
            scheduledCount++;
          }
        }

        // 4. Event End notification
        if (notifyEnd && endLocal.isAfter(now)) {
          final tz.TZDateTime tzEnd = _toTZDateTime(endLocal);
          debugPrint('→ Scheduling END for "${event.name}" at $tzEnd');
          await _scheduleNotification(
            id: notificationId++,
            title: "Ingress Event Ending: ${event.name}",
            body: "Gameplay changes are reverting back to default. Stand down.",
            scheduledTime: tzEnd,
            payload: event.name,
          );
          scheduledCount++;
        }
      }
    }
    debugPrint('Finished scheduling. $scheduledCount alarms registered. Next ID: $notificationId');
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
      icon: 'ic_notification',
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
