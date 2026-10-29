import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/cards_repo.dart';
import '../data/study_repo.dart';
import '../mascot/ghost.dart';
import '../mascot/mascot.dart';
import '../mascot/messages.dart';
import '../theme/app_theme.dart';

/// Flip through cards. "Again" puts a card back in the queue,
/// "Got it" moves it up a box so it comes back later.
class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, required this.deck});
  final Deck deck;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  final List<CueCard> _queue = [];
  bool _loading = true;
  bool _showBack = false;
  bool _studyingAll = false;
  int _gotIt = 0;
  int _again = 0;

  @override
  void initState() {
    super.initState();
    _load(all: false);
  }

  Future<void> _load({required bool all}) async {
    final cards = all
        ? await CardsRepo.cards(widget.deck.id)
        : await CardsRepo.dueCards(widget.deck.id);
    cards.shuffle();
    if (!mounted) return;
    setState(() {
      _queue
        ..clear()
        ..addAll(cards);
      _studyingAll = all;
      _loading = false;
      _showBack = false;
    });
  }

  Future<void> _answer(bool gotIt) async {
    final card = _queue.removeAt(0);
    await CardsRepo.answer(card, gotIt);
    await StudyRepo.logReview(card.id, gotIt);
    setState(() {
      if (gotIt) {
        _gotIt++;
      } else {
        _again++;
        _queue.add(card); // see it again this session
      }
      _showBack = false;
    });
    if (_queue.isEmpty) {
      Mascot.instance.say(MessageBank.pick(MessageBank.cardsDone), pose: GhostPose.heart);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deck.name),
        actions: [
          if (_queue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: AppSpace.l),
              child: Center(
                child: Text('${_queue.length} left',
                    style: const TextStyle(color: AppPalette.muted)),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _queue.isEmpty
              ? _finished(context)
              : _studying(context),
    );
  }

  Widget _studying(BuildContext context) {
    final card = _queue.first;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.l),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720, maxHeight: 440),
                child: GestureDetector(
                  onTap: () => setState(() => _showBack = !_showBack),
                  child: _FlipCard(
                    key: ValueKey('${card.id}-${_gotIt + _again}'),
                    showBack: _showBack,
                    front: card.front,
                    back: card.back,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.l),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: !_showBack
                ? FilledButton.tonal(
                    key: const ValueKey('flip'),
                    onPressed: () => setState(() => _showBack = true),
                    style: FilledButton.styleFrom(minimumSize: const Size(220, 54)),
                    child: const Text('Show answer'),
                  )
                : Row(
                    key: const ValueKey('answer'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _answer(false),
                        icon: const Icon(Icons.replay),
                        label: const Text('Again'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(160, 54)),
                      ),
                      const SizedBox(width: AppSpace.m),
                      FilledButton.icon(
                        onPressed: () => _answer(true),
                        icon: const Icon(Icons.check),
                        label: const Text('Got it'),
                        style: FilledButton.styleFrom(minimumSize: const Size(160, 54)),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _finished(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final nothingDue = _gotIt + _again == 0;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        MascotWithBubble(height: 160, bubbleOnRight: false, overridePose: GhostPose.heart),
        const SizedBox(height: AppSpace.l),
        Text(nothingDue ? 'Nothing due right now' : 'Deck done!', style: t.headlineSmall),
        const SizedBox(height: AppSpace.s),
        Text(
          nothingDue
              ? 'You\'ve reviewed everything in this deck recently.'
              : '$_gotIt got it · $_again again',
          style: const TextStyle(color: AppPalette.muted),
        ),
        const SizedBox(height: AppSpace.l),
        Wrap(spacing: AppSpace.m, children: [
          if (!_studyingAll || !nothingDue)
            OutlinedButton(
              onPressed: () {
                _gotIt = 0;
                _again = 0;
                _load(all: true);
              },
              child: const Text('Study all cards anyway'),
            ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ]),
      ]),
    );
  }
}

class _FlipCard extends StatelessWidget {
  const _FlipCard({super.key, required this.showBack, required this.front, required this.back});
  final bool showBack;
  final String front;
  final String back;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: showBack ? 1 : 0),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOut,
      builder: (context, v, _) {
        final angle = v * math.pi;
        final isBack = v >= 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle),
          child: isBack
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: _face(context, back, 'Answer'),
                )
              : _face(context, front, 'Question'),
        );
      },
    );
  }

  Widget _face(BuildContext context, String text, String label) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black26,
      child: SizedBox.expand(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            children: [
              Text(label.toUpperCase(),
                  style: const TextStyle(color: AppPalette.muted, letterSpacing: 1.2, fontSize: 12)),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(height: 1.35),
                    ),
                  ),
                ),
              ),
              const Text('tap to flip', style: TextStyle(color: AppPalette.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
