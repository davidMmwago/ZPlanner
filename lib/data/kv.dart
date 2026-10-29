import 'package:sqflite/sqflite.dart';

import 'db.dart';

/// Tiny key/value store for settings and "seen this tip" flags.
class Kv {
  static Future<String?> get(String k) async {
    final rows = await (await AppDb.instance.db)
        .query('kv', where: 'k = ?', whereArgs: [k], limit: 1);
    return rows.isEmpty ? null : rows.first['v'] as String?;
  }

  static Future<void> set(String k, String v) async {
    await (await AppDb.instance.db).insert('kv', {'k': k, 'v': v},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
