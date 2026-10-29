import 'db.dart';

class Todo {
  final int id;
  final String title;
  final DateTime? due;
  final bool hasTime;
  final bool done;
  final int? moduleId;
  final String? moduleName;
  final int? moduleColor;

  /// Linked Google Calendar event (if synced).
  final String? gcalId;
  const Todo({
    required this.id,
    required this.title,
    this.due,
    this.hasTime = false,
    this.done = false,
    this.moduleId,
    this.moduleName,
    this.moduleColor,
    this.gcalId,
  });
}

class TodoRepo {
  static Future<List<Todo>> all() async {
    final rows = await (await AppDb.instance.db).rawQuery('''
      SELECT t.*, m.name AS module_name, m.color AS module_color
      FROM todos t LEFT JOIN modules m ON m.id = t.module_id
      ORDER BY t.done, t.due IS NULL, t.due, t.created''');
    return [
      for (final r in rows)
        Todo(
          id: r['id'] as int,
          title: r['title'] as String,
          due: r['due'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['due'] as int),
          hasTime: (r['has_time'] as int) == 1,
          done: (r['done'] as int) == 1,
          moduleId: r['module_id'] as int?,
          moduleName: r['module_name'] as String?,
          moduleColor: r['module_color'] as int?,
          gcalId: r['gcal_id'] as String?,
        )
    ];
  }

  static Future<Todo?> get(int id) async {
    final all = await TodoRepo.all();
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  static Future<void> setGcalId(int id, String? gcalId) async => (await AppDb.instance.db)
      .update('todos', {'gcal_id': gcalId}, where: 'id = ?', whereArgs: [id]);

  static Map<String, Object?> _row(String title, DateTime? due, bool hasTime, int? moduleId) => {
        'title': title,
        'due': due?.millisecondsSinceEpoch,
        'has_time': hasTime ? 1 : 0,
        'module_id': moduleId,
      };

  static Future<int> add(String title, DateTime? due, bool hasTime, int? moduleId) async =>
      (await AppDb.instance.db).insert('todos', {
        ..._row(title, due, hasTime, moduleId),
        'created': DateTime.now().millisecondsSinceEpoch,
      });

  static Future<void> update(int id, String title, DateTime? due, bool hasTime, int? moduleId) async =>
      (await AppDb.instance.db)
          .update('todos', _row(title, due, hasTime, moduleId), where: 'id = ?', whereArgs: [id]);

  static Future<void> setDone(int id, bool done) async => (await AppDb.instance.db).update(
      'todos', {'done': done ? 1 : 0, 'done_at': done ? DateTime.now().millisecondsSinceEpoch : null},
      where: 'id = ?', whereArgs: [id]);

  static Future<void> delete(int id) async =>
      (await AppDb.instance.db).delete('todos', where: 'id = ?', whereArgs: [id]);
}
