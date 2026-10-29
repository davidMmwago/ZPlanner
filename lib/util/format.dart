import '../theme/app_theme.dart';

const monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
const weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String two(int n) => n.toString().padLeft(2, '0');

String hhmm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

/// "Today", "Tomorrow", "Yesterday" or "Mon 3 Sep".
String friendlyDay(DateTime d) {
  final today = dayOnly(DateTime.now());
  final diff = dayOnly(d).difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return '${weekdaysShort[d.weekday - 1]} ${d.day} ${monthsShort[d.month - 1]}';
}

/// "1h 25m", "40m"
String minutesText(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// "R 1 234.50"
String money(double v, {bool sign = false}) {
  final neg = v < 0;
  final cents = (v.abs() * 100).round();
  final whole = (cents ~/ 100).toString();
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(' ');
    buf.write(whole[i]);
  }
  final s = '${AppConfig.currency} $buf.${two(cents % 100)}';
  if (neg) return '−$s';
  return sign ? '+$s' : s;
}
