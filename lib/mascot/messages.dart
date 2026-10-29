import 'dart:math' as math;

import '../theme/app_theme.dart';

/// Everything the ghost can say.
/// ✏️ Edit freely — especially [fromYou]. Those are the personal ones.
class MessageBank {
  static final _rng = math.Random();
  static final Map<List<String>, int> _last = {};

  /// Picks a random line, never the same one twice in a row.
  static String pick(List<String> list) {
    if (list.isEmpty) return '';
    if (list.length == 1) return _fill(list.first);
    var i = _rng.nextInt(list.length);
    if (_last[list] == i) i = (i + 1) % list.length;
    _last[list] = i;
    return _fill(list[i]);
  }

  static String _fill(String s) => s
      .replaceAll('{name}', AppConfig.herName)
      .replaceAll('{ghost}', AppConfig.mascotName);

  /// Tapping the ghost: a mix of everything below.
  /// Returns the line and whether it's one of your personal ones.
  static (String, bool) random() {
    final r = _rng.nextDouble();
    if (r < 0.35) return (pick(fromYou), true);
    if (r < 0.65) return (pick(inspire), false);
    if (r < 0.90) return (pick(jokes), false);
    return (pick(generalTips), false);
  }

  // ── ✏️ YOUR MESSAGES (placeholders, replace with your own) ──
  static const fromYou = [
    'Lock in twin',
    'Drink some water',
    'You\'ve got this',
    'Proud of you for sitting down to do this.',
    'Reminder: you\'re doing better than you think.',
  ];

  static const inspire = [
    'Small steps still move you forward.',
    'You don\'t have to be perfect, just consistent.',
    'Future {name} is going to be grateful for this.',
    'One page at a time',
    'Done is better than perfect.',
    'It gets easier but you gotta do it every day, thats the hard part',
  ];

  static const jokes = [
    'Why did the ghost go to university? To get a boo-chelor\'s degree.',
    'Jokes are hard, I hope you did\'nt expect this to be funny',
    'What\'s a ghost\'s favourite subject? Boo-logy.',
    'Why are ghosts bad liars? You can see right through them.',    
    'What do ghosts put on their toast? Scream cheese.',
  ];

  // ── Focus timer ──
  static const focusStart = [
    'Let\'s go! I\'ll keep watch.',
    'Phone down, brain on. You\'ve got this.',    
  ];
  static const focusMid = [
    'Halfway there! Keep going.',
    'You\'re doing great. Stay with it.',
    'Stop clicking on me and lock in',
    'Keep going.',
  ];
  static const focusDone = [
    'Session done! Take a proper break.',
    'Stretch, water, snack. You earned it.',
    'Another one in the bag.',
  ];
  static const breakDone = [
    'Break\'s over, work is not gonna do itself',
    'Recharged? Let\'s do one more.',
  ];

  // ── Other moments ──
  static const cardsDone = [
    'Deck finished! Your brain just got a little bigger.',
    'All cards done. Look at you go!',
  ];
  static const todoDone = [
    'Ticked off! ✔',
    'One less thing. Nice.',
    'Look at you getting things done.',
  ];
  static const greeting = [
    'Hi {name}! Tap me any time.',
    'Welcome back, {name}!',
    'Boo! Ready to study?',
  ];

  // ── How-to tips (shown once per section, then randomly) ──
  static const generalTips = [
    'Tip: long-press almost anything to rename or delete it.',
    'Tip: tap me whenever you need a pick-me-up.',
  ];
  static const sectionTips = <String, String>{
    'Modules': 'Make a module for each subject. Long-press one to rename it or change its colour.',
    'Focus': 'Pick a module, then press start. Every session counts towards your streak!',
    'Cue cards': 'Make a deck, add cards, then press Study. Cards you know come back less often.',
    'Planner': 'Add your to-dos here. Tick them off when they\'re done.',
    'Money': 'Plan what\'s coming in and going out each month. Turn on "every month" for things like rent.',
    'Stats': 'Your study time and streaks live here. Study a little each day to keep the streak going.',
  };
}
