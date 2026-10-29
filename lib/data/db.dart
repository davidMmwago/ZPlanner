import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app_files.dart';
import 'models.dart';

/// Local SQLite database. Everything is stored on the tablet.
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  Database? _db;
  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'zee.db'),
      version: 3,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _createV1(db);
        await _createV2(db);
        await _createV3(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createV2(db);
        if (oldVersion < 3) await _createV3(db);
      },
    );
  }

  // v1: modules + documents/notes
  static Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE modules(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        created INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        module_id INTEGER NOT NULL REFERENCES modules(id) ON DELETE CASCADE,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        file_path TEXT,
        page_count INTEGER NOT NULL DEFAULT 1,
        updated INTEGER NOT NULL
      )''');
  }

  // v2: focus sessions, cue cards, to-dos, money, settings
  static Future<void> _createV2(Database db) async {
    await db.execute('''
      CREATE TABLE sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        module_id INTEGER REFERENCES modules(id) ON DELETE SET NULL,
        started INTEGER NOT NULL,
        minutes INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE decks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        module_id INTEGER REFERENCES modules(id) ON DELETE SET NULL,
        name TEXT NOT NULL,
        created INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE cards(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        deck_id INTEGER NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
        front TEXT NOT NULL,
        back TEXT NOT NULL,
        box INTEGER NOT NULL DEFAULT 0,
        due INTEGER NOT NULL,
        created INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE reviews(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        card_id INTEGER,
        ts INTEGER NOT NULL,
        correct INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE todos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        due INTEGER,
        has_time INTEGER NOT NULL DEFAULT 0,
        done INTEGER NOT NULL DEFAULT 0,
        done_at INTEGER,
        module_id INTEGER REFERENCES modules(id) ON DELETE SET NULL,
        created INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE money(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        is_income INTEGER NOT NULL,
        date INTEGER NOT NULL,
        monthly INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('CREATE TABLE kv(k TEXT PRIMARY KEY, v TEXT)');
  }

  // v3: link to-dos to Google Calendar events
  static Future<void> _createV3(Database db) async {
    await db.execute('ALTER TABLE todos ADD COLUMN gcal_id TEXT');
  }

  /// Full path of the database file (used by backup/restore).
  Future<String> dbPath() async => p.join(await getDatabasesPath(), 'zee.db');

  /// Closes the database (backup/restore). It reopens on next use.
  Future<void> close() async {
    final d = _db;
    _db = null;
    await d?.close();
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  // ── Modules ────────────────────────────────────────────────
  Future<List<Module>> modules() async {
    final rows = await (await db).rawQuery('''
      SELECT m.*, (SELECT COUNT(*) FROM items i WHERE i.module_id = m.id) AS item_count
      FROM modules m ORDER BY m.name COLLATE NOCASE''');
    return rows.map(Module.fromMap).toList();
  }

  Future<int> addModule(String name, int color) async =>
      (await db).insert('modules', {'name': name, 'color': color, 'created': _now});

  Future<void> updateModule(int id, {String? name, int? color}) async {
    await (await db).update(
      'modules',
      {if (name != null) 'name': name, if (color != null) 'color': color},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteModule(int id) async {
    for (final item in await items(id)) {
      await AppFiles.deleteItemFiles(item);
    }
    await (await db).delete('modules', where: 'id = ?', whereArgs: [id]);
  }

  // ── Items (PDFs + notes) ───────────────────────────────────
  Future<List<StudyItem>> items(int moduleId) async {
    final rows = await (await db).query('items',
        where: 'module_id = ?', whereArgs: [moduleId], orderBy: 'updated DESC');
    return rows.map(StudyItem.fromMap).toList();
  }

  Future<int> addItem({
    required int moduleId,
    required ItemType type,
    required String title,
    String? fileName,
    int pageCount = 1,
  }) async =>
      (await db).insert('items', {
        'module_id': moduleId,
        'type': type.name,
        'title': title,
        'file_path': fileName,
        'page_count': pageCount,
        'updated': _now,
      });

  Future<StudyItem?> item(int id) async {
    final rows = await (await db).query('items', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : StudyItem.fromMap(rows.first);
  }

  /// Every PDF and note across all modules (for "open beside").
  Future<List<ItemWithModule>> allDocs() async {
    final rows = await (await db).rawQuery('''
      SELECT i.*, m.name AS module_name, m.color AS module_color
      FROM items i JOIN modules m ON m.id = i.module_id
      WHERE i.type IN ('pdf', 'note')
      ORDER BY m.name COLLATE NOCASE, i.updated DESC''');
    return [
      for (final r in rows)
        ItemWithModule(StudyItem.fromMap(r), r['module_name'] as String, r['module_color'] as int)
    ];
  }

  Future<void> renameItem(int id, String title) async => (await db)
      .update('items', {'title': title}, where: 'id = ?', whereArgs: [id]);

  Future<void> setPageCount(int id, int count) async => (await db).update(
      'items', {'page_count': count, 'updated': _now},
      where: 'id = ?', whereArgs: [id]);

  Future<void> touchItem(int id) async => (await db)
      .update('items', {'updated': _now}, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteItem(StudyItem item) async {
    await AppFiles.deleteItemFiles(item);
    await (await db).delete('items', where: 'id = ?', whereArgs: [item.id]);
  }
}
