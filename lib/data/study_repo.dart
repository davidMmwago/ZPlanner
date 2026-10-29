import 'db.dart';
import '../util/format.dart';

/// Focus sessions + the numbers behind the Stats page.
class StudyRepo {
  static Future<void> logSession({int? moduleId, required DateTime started, required int minutes}) async {
    if (minutes <= 0) return;
    await (await AppDb.instance.db).insert('sessions', {
      'module_id': moduleId,
      'started': started.millisecondsSinceEpoch,
      'minutes': minutes,
    });
  }

  static Future<void> logReview(int cardId, bool correct) async {
    await (await AppDb.instance.db).insert('reviews', {
      'card_id': cardId,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'correct': correct ? 1 : 0,
    });
  }

  /// Focus minutes per day for the last [days] days (oldest first).
  static Future<List<({DateTime day, int minutes})>> minutesPerDay(int days) async {
    final today = dayOnly(DateTime.now());
    final from = today.subtract(Duration(days: days - 1));
    final rows = await (await AppDb.instance.db).query('sessions',
        columns: ['started', 'minutes'],
        where: 'started >= ?',
        whereArgs: [from.millisecondsSinceEpoch]);
    final totals = List<int>.filled(days, 0);
    for (final r in rows) {
      final d = dayOnly(DateTime.fromMillisecondsSinceEpoch(r['started'] as int));
      final i = d.difference(from).inDays;
      if (i >= 0 && i < days) totals[i] += r['minutes'] as int;
    }
    return [
      for (var i = 0; i < days; i++)
        (day: from.add(Duration(days: i)), minutes: totals[i])
    ];
  }

  /// Minutes per module since [from], biggest first.
  static Future<List<({String name, int color, int minutes})>> minutesPerModule(DateTime from) async {
    final rows = await (await AppDb.instance.db).rawQuery('''
      SELECT COALESCE(m.name, 'No module') AS name,
             COALESCE(m.color, 4287268759) AS color,
             SUM(s.minutes) AS minutes
      FROM sessions s LEFT JOIN modules m ON m.id = s.module_id
      WHERE s.started >= ?
      GROUP BY s.module_id
      ORDER BY minutes DESC''', [from.millisecondsSinceEpoch]);
    return [
      for (final r in rows)
        (name: r['name'] as String, color: r['color'] as int, minutes: (r['minutes'] as num).toInt())
    ];
  }

  static Future<int> reviewsSince(DateTime from) async {
    final rows = await (await AppDb.instance.db).rawQuery(
        'SELECT COUNT(*) AS c FROM reviews WHERE ts >= ?', [from.millisecondsSinceEpoch]);
    return (rows.first['c'] as num).toInt();
  }

  static Future<int> sessionsSince(DateTime from) async {
    final rows = await (await AppDb.instance.db).rawQuery(
        'SELECT COUNT(*) AS c FROM sessions WHERE started >= ?', [from.millisecondsSinceEpoch]);
    return (rows.first['c'] as num).toInt();
  }

  /// A day counts towards the streak if she did a focus session or reviewed cards.
  static Future<({int current, int best})> streaks() async {
    final db = await AppDb.instance.db;
    final s = await db.query('sessions', columns: ['started']);
    final r = await db.query('reviews', columns: ['ts']);
    final days = <DateTime>{
      for (final row in s) dayOnly(DateTime.fromMillisecondsSinceEpoch(row['started'] as int)),
      for (final row in r) dayOnly(DateTime.fromMillisecondsSinceEpoch(row['ts'] as int)),
    };
    if (days.isEmpty) return (current: 0, best: 0);

    // Current: count back from today (or yesterday, so the streak isn't
    // "lost" in the morning before she's studied).
    var cursor = dayOnly(DateTime.now());
    if (!days.contains(cursor)) cursor = cursor.subtract(const Duration(days: 1));
    var current = 0;
    while (days.contains(cursor)) {
      current++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    final sorted = days.toList()..sort();
    var best = 1, run = 1;
    for (var i = 1; i < sorted.length; i++) {
      // Compare calendar days (safe across daylight-saving changes).
      final next = DateTime(sorted[i - 1].year, sorted[i - 1].month, sorted[i - 1].day + 1);
      run = sameDay(next, sorted[i]) ? run + 1 : 1;
      if (run > best) best = run;
    }
    return (current: current, best: best);
  }
}
