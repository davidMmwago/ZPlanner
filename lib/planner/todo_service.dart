import 'package:flutter/foundation.dart';

import '../data/todo_repo.dart';
import '../google/google_api.dart';
import '../google/google_auth.dart';
import '../notify/notifier.dart';

/// Saves to-dos and keeps their reminder and Google Calendar event in step.
/// Calendar problems never block saving; they're returned as a message.
class TodoService {
  static bool get _google => GoogleAuth.instance.signedIn;

  /// Returns an error message about the calendar, or null.
  static Future<String?> add(String title, DateTime? due, bool hasTime, int? moduleId,
      {required bool toCalendar}) async {
    final id = await TodoRepo.add(title, due, hasTime, moduleId);
    final t = await TodoRepo.get(id);
    if (t != null) await Notifier.scheduleTodo(t);
    if (toCalendar && _google && due != null) {
      try {
        await TodoRepo.setGcalId(id, await GoogleApi.createEvent(title, due, hasTime));
      } catch (e) {
        return 'Saved, but couldn\'t add it to Google Calendar: $e';
      }
    }
    return null;
  }

  static Future<String?> update(Todo old, String title, DateTime? due, bool hasTime, int? moduleId,
      {required bool toCalendar}) async {
    await TodoRepo.update(old.id, title, due, hasTime, moduleId);
    final t = await TodoRepo.get(old.id);
    if (t != null) await Notifier.scheduleTodo(t);
    if (!_google) return null;
    try {
      final gid = old.gcalId;
      if (gid != null && (!toCalendar || due == null)) {
        await GoogleApi.deleteEvent(gid);
        await TodoRepo.setGcalId(old.id, null);
      } else if (gid != null && due != null) {
        await GoogleApi.updateEvent(gid, title, due, hasTime);
      } else if (gid == null && toCalendar && due != null) {
        await TodoRepo.setGcalId(old.id, await GoogleApi.createEvent(title, due, hasTime));
      }
    } catch (e) {
      return 'Saved, but Google Calendar wasn\'t updated: $e';
    }
    return null;
  }

  /// Ticking a to-do marks its calendar event with ✓ (unticking removes it).
  static Future<void> setDone(Todo t, bool done) async {
    await TodoRepo.setDone(t.id, done);
    if (done) {
      await Notifier.cancelTodo(t.id);
    } else {
      final fresh = await TodoRepo.get(t.id);
      if (fresh != null) await Notifier.scheduleTodo(fresh);
    }
    final gid = t.gcalId, due = t.due;
    if (_google && gid != null && due != null) {
      try {
        await GoogleApi.updateEvent(gid, done ? '✓ ${t.title}' : t.title, due, t.hasTime);
      } catch (e) {
        debugPrint('Calendar update failed: $e');
      }
    }
  }

  static Future<void> delete(Todo t) async {
    await TodoRepo.delete(t.id);
    await Notifier.cancelTodo(t.id);
    final gid = t.gcalId;
    if (_google && gid != null) {
      try {
        await GoogleApi.deleteEvent(gid);
      } catch (e) {
        debugPrint('Calendar delete failed: $e');
      }
    }
  }
}
