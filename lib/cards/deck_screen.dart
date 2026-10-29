import 'package:flutter/material.dart';

import '../data/cards_repo.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'study_screen.dart';

/// List of cards in a deck: add, edit, delete, then study.
class DeckScreen extends StatefulWidget {
  const DeckScreen({super.key, required this.deck});
  final Deck deck;

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
  List<CueCard>? _cards;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final c = await CardsRepo.cards(widget.deck.id);
    if (mounted) setState(() => _cards = c);
  }

  /// Opens the editor. "Save & next" keeps it open for fast entry.
  Future<void> _edit([CueCard? card]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CardEditor(
        card: card,
        onSave: (front, back) async {
          if (card == null) {
            await CardsRepo.addCard(widget.deck.id, front, back);
          } else {
            await CardsRepo.updateCard(card.id, front, back);
          }
          await _refresh();
        },
      ),
    );
  }

  Future<void> _delete(CueCard c) async {
    if (await confirmDelete(context, 'this card')) {
      await CardsRepo.deleteCard(c.id);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deck.name),
        actions: [
          FilledButton.icon(
            onPressed: (cards == null || cards.isEmpty)
                ? null
                : () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => StudyScreen(deck: widget.deck)));
                    _refresh();
                  },
            icon: const Icon(Icons.school_outlined),
            label: const Text('Study'),
          ),
          const SizedBox(width: AppSpace.m),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add card'),
      ),
      body: cards == null
          ? const Center(child: CircularProgressIndicator())
          : cards.isEmpty
              ? const EmptyState(title: 'No cards yet', subtitle: 'Tap "Add card" to write your first one.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpace.l, AppSpace.s, AppSpace.l, 100),
                  itemCount: cards.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpace.s),
                  itemBuilder: (context, i) {
                    final c = cards[i];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.m, vertical: 4),
                        title: Text(c.front, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(c.back,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppPalette.muted)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(c),
                        ),
                        onTap: () => _edit(c),
                      ),
                    );
                  },
                ),
    );
  }
}

class _CardEditor extends StatefulWidget {
  const _CardEditor({this.card, required this.onSave});
  final CueCard? card;
  final Future<void> Function(String front, String back) onSave;

  @override
  State<_CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends State<_CardEditor> {
  late final _front = TextEditingController(text: widget.card?.front);
  late final _back = TextEditingController(text: widget.card?.back);
  final _frontFocus = FocusNode();
  int _added = 0;

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    _frontFocus.dispose();
    super.dispose();
  }

  Future<bool> _save() async {
    final f = _front.text.trim(), b = _back.text.trim();
    if (f.isEmpty || b.isEmpty) return false;
    await widget.onSave(f, b);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.card == null;
    return AlertDialog(
      title: Text(isNew ? 'New card${_added > 0 ? ' ($_added added)' : ''}' : 'Edit card'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _front,
            focusNode: _frontFocus,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Front (question)'),
          ),
          const SizedBox(height: AppSpace.m),
          TextField(
            controller: _back,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Back (answer)'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        if (isNew)
          TextButton(
            onPressed: () async {
              if (await _save()) {
                _front.clear();
                _back.clear();
                setState(() => _added++);
                _frontFocus.requestFocus();
              }
            },
            child: const Text('Save & next'),
          ),
        FilledButton(
          onPressed: () async {
            if (await _save() && context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
