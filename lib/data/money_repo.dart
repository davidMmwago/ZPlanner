import 'db.dart';

class MoneyEntry {
  final int id;
  final String title;
  final double amount; // always positive
  final bool isIncome;
  final DateTime date;
  final bool monthly;
  const MoneyEntry({
    required this.id,
    required this.title,
    required this.amount,
    required this.isIncome,
    required this.date,
    required this.monthly,
  });

  double get signed => isIncome ? amount : -amount;

  /// Does this entry happen in the given month?
  bool occursIn(int year, int month) {
    final start = DateTime(date.year, date.month);
    final target = DateTime(year, month);
    if (monthly) return !target.isBefore(start);
    return date.year == year && date.month == month;
  }
}

class MoneyRepo {
  static Future<List<MoneyEntry>> all() async {
    final rows = await (await AppDb.instance.db).query('money', orderBy: 'date');
    return [
      for (final r in rows)
        MoneyEntry(
          id: r['id'] as int,
          title: r['title'] as String,
          amount: (r['amount'] as num).toDouble(),
          isIncome: (r['is_income'] as int) == 1,
          date: DateTime.fromMillisecondsSinceEpoch(r['date'] as int),
          monthly: (r['monthly'] as int) == 1,
        )
    ];
  }

  static Map<String, Object?> _row(String title, double amount, bool isIncome, DateTime date, bool monthly) => {
        'title': title,
        'amount': amount,
        'is_income': isIncome ? 1 : 0,
        'date': date.millisecondsSinceEpoch,
        'monthly': monthly ? 1 : 0,
      };

  static Future<void> add(String title, double amount, bool isIncome, DateTime date, bool monthly) async =>
      (await AppDb.instance.db).insert('money', _row(title, amount, isIncome, date, monthly));

  static Future<void> update(int id, String title, double amount, bool isIncome, DateTime date, bool monthly) async =>
      (await AppDb.instance.db).update('money', _row(title, amount, isIncome, date, monthly),
          where: 'id = ?', whereArgs: [id]);

  static Future<void> delete(int id) async =>
      (await AppDb.instance.db).delete('money', where: 'id = ?', whereArgs: [id]);
}
