import 'db.dart';

class Deck {
  final int id;
  final int? moduleId;
  final String name;
  final int cardCount;
  final int dueCount;
  final String? moduleName;
  final int? moduleColor;
  const Deck({
    required this.id,
    required this.moduleId,
    required this.name,
    this.cardCount = 0,
    this.dueCount = 0,
    this.moduleName,
    this.moduleColor,
  });
}

class CueCard {
  final int id;
  final int deckId;
  final String front;
  final String back;
  final int box;
  final DateTime due;
  const CueCard({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    required this.box,
    required this.due,
  });

  factory CueCard.fromMap(Map<String, Object?> m) => CueCard(
        id: m['id'] as int,
        deckId: m['deck_id'] as int,
        front: m['front'] as String,
        back: m['back'] as String,
        box: m['box'] as int,
        due: DateTime.fromMillisecondsSinceEpoch(m['due'] as int),
      );
}

/// Cue cards with a simple Leitner system:
/// "Got it" moves a card up a box (seen less often), "Again" sends it to box 0.
class CardsRepo {
  /// Days until a card in box N comes back.
  static const intervals = [0, 1, 2, 4, 8, 16];

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  static Future<List<Deck>> decks() async {
    final rows = await (await AppDb.instance.db).rawQuery('''
      SELECT d.*, m.name AS module_name, m.color AS module_color,
        (SELECT COUNT(*) FROM cards c WHERE c.deck_id = d.id) AS card_count,
        (SELECT COUNT(*) FROM cards c WHERE c.deck_id = d.id AND c.due <= ?) AS due_count
      FROM decks d LEFT JOIN modules m ON m.id = d.module_id
      ORDER BY d.name COLLATE NOCASE''', [_now]);
    return [
      for (final r in rows)
        Deck(
          id: r['id'] as int,
          moduleId: r['module_id'] as int?,
          name: r['name'] as String,
          cardCount: (r['card_count'] as num).toInt(),
          dueCount: (r['due_count'] as num).toInt(),
          moduleName: r['module_name'] as String?,
          moduleColor: r['module_color'] as int?,
        )
    ];
  }

  static Future<int> addDeck(String name, int? moduleId) async =>
      (await AppDb.instance.db).insert('decks', {'name': name, 'module_id': moduleId, 'created': _now});

  static Future<void> updateDeck(int id, String name, int? moduleId) async =>
      (await AppDb.instance.db).update('decks', {'name': name, 'module_id': moduleId},
          where: 'id = ?', whereArgs: [id]);

  static Future<void> deleteDeck(int id) async =>
      (await AppDb.instance.db).delete('decks', where: 'id = ?', whereArgs: [id]);

  static Future<List<CueCard>> cards(int deckId) async {
    final rows = await (await AppDb.instance.db)
        .query('cards', where: 'deck_id = ?', whereArgs: [deckId], orderBy: 'created');
    return rows.map(CueCard.fromMap).toList();
  }

  static Future<List<CueCard>> dueCards(int deckId) async {
    final rows = await (await AppDb.instance.db).query('cards',
        where: 'deck_id = ? AND due <= ?', whereArgs: [deckId, _now], orderBy: 'due');
    return rows.map(CueCard.fromMap).toList();
  }

  static Future<void> addCard(int deckId, String front, String back) async =>
      (await AppDb.instance.db).insert('cards', {
        'deck_id': deckId,
        'front': front,
        'back': back,
        'box': 0,
        'due': _now,
        'created': _now,
      });

  static Future<void> updateCard(int id, String front, String back) async =>
      (await AppDb.instance.db).update('cards', {'front': front, 'back': back},
          where: 'id = ?', whereArgs: [id]);

  static Future<void> deleteCard(int id) async =>
      (await AppDb.instance.db).delete('cards', where: 'id = ?', whereArgs: [id]);

  static Future<void> answer(CueCard c, bool gotIt) async {
    final box = gotIt ? (c.box + 1).clamp(0, intervals.length - 1).toInt() : 0;
    final due = DateTime.now().add(Duration(days: intervals[box]));
    await (await AppDb.instance.db).update(
        'cards', {'box': box, 'due': due.millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [c.id]);
  }
}
