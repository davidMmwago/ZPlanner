import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/kv.dart';
import '../data/todo_repo.dart';
import '../theme/app_theme.dart';

/// Local notifications (no internet or Google needed):
/// the Focus timer finishing, and to-do reminders.
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static bool _exact = false;

  static const _focusId = 1;
  static int _todoId(int todoId) => 100000 + todoId;

  static const _focusDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'focus',
      'Focus timer',
      channelDescription: 'When a focus session or break ends',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static const _reminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'To-do reminders',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation(await _localZone()));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _exact = await _android?.canScheduleExactNotifications() ?? false;
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  static Future<String> _localZone() async {
    try {
      final dynamic info = await FlutterTimezone.getLocalTimezone();
      if (info is String) return info;
      try {
        return info.identifier as String;
      } catch (_) {
        return info.name as String;
      }
    } catch (_) {
      return AppConfig.timeZone;
    }
  }

  /// Asks for notification permission once (Android 13+ shows a prompt),
  /// and once for exact alarms so timers ring on time.
  static Future<void> askPermissionsOnce() async {
    if (!_ready) return;
    if (await Kv.get('notif_asked') == null) {
      await Kv.set('notif_asked', '1');
      await _android?.requestNotificationsPermission();
      if (!_exact) {
        await _android?.requestExactAlarmsPermission();
        _exact = await _android?.canScheduleExactNotifications() ?? false;
      }
    }
  }

  static AndroidScheduleMode get _mode =>
      _exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;

  static Future<void> _schedule(int id, DateTime when, String title, String body, NotificationDetails d) async {
    if (!_ready || when.isBefore(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: d,
        androidScheduleMode: _mode,
        title: title,
        body: body,
      );
    } catch (e) {
      debugPrint('Could not schedule notification: $e');
    }
  }

  static Future<void> _cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  // ── Focus timer ────────────────────────────────────────────
  static Future<void> focusEndsAt(DateTime when, {required bool isBreak}) => _schedule(
        _focusId,
        when,
        isBreak ? 'Break\'s over' : 'Focus session done! 🌸',
        isBreak ? 'Ready for another round?' : 'Time for a break, ${AppConfig.herName}.',
        _focusDetails,
      );

  static Future<void> cancelFocus() => _cancel(_focusId);

  // ── To-dos ─────────────────────────────────────────────────
  /// Timed to-dos remind at their time; date-only ones at 08:00 that day.
  static Future<void> scheduleTodo(Todo t) async {
    final due = t.due;
    if (t.done || due == null) return cancelTodo(t.id);
    final when = t.hasTime ? due : DateTime(due.year, due.month, due.day, 8);
    await _schedule(_todoId(t.id), when, t.title,
        t.hasTime ? 'Due now' : 'Due today', _reminderDetails);
  }

  static Future<void> cancelTodo(int todoId) => _cancel(_todoId(todoId));

  /// Re-schedules every open to-do (on app start).
  static Future<void> rescheduleAllTodos() async {
    if (!_ready) return;
    for (final t in await TodoRepo.all()) {
      if (!t.done && t.due != null && t.due!.isAfter(DateTime.now())) {
        await scheduleTodo(t);
      }
    }
  }

  static Future<void> test() async {
    if (!_ready) return;
    await _plugin.show(
      id: 999,
      title: 'Hi ${AppConfig.herName}! 👻',
      body: 'Notifications are working.',
      notificationDetails: _reminderDetails,
    );
  }
}
