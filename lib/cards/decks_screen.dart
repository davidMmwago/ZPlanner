import 'package:flutter/material.dart';

import '../data/cards_repo.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'deck_screen.dart';
import 'study_screen.dart';

class DecksScreen extends StatefulWidget {
  const DecksScreen({super.key});

  @override
  State<DecksScreen> createState() => _DecksScreenState();
}

class _DecksScreenState extends State<DecksScreen> {
  List<Deck>? _decks;
  List<Module> _modules = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final d = await CardsRepo.decks();
    final m = await AppDb.instance.modules();
    if (mounted) {
      setState(() {
        _decks = d;
        _modules = m;
      });
    }
  }

  Future<void> _editDeck([Deck? deck]) async {
    final result = await showDeckDialog(context, _modules, deck);
    if (result == null) return;
    if (deck == null) {
      final id = await CardsRepo.addDeck(result.$1, result.$2);
      await _refresh();
      final created = _decks?.where((d) => d.id == id);
      if (created != null && created.isNotEmpty && mounted) await _open(created.first);
    } else {
      await CardsRepo.updateDeck(deck.id, result.$1, result.$2);
      _refresh();
    }
  }

  Future<void> _open(Deck d) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DeckScreen(deck: d)));
    _refresh();
  }

  Future<void> _study(Deck d) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => StudyScreen(deck: d)));
    _refresh();
  }

  Future<void> _options(Deck d) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename / change module'),
            onTap: () => Navigator.pop(context, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete deck'),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') {
      _editDeck(d);
    } else if (action == 'delete' &&
        await confirmDelete(context, '"${d.name}"', detail: 'All ${d.cardCount} cards will be deleted.')) {
      await CardsRepo.deleteDeck(d.id);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final decks = _decks;
    return Scaffold(
      appBar: const SectionAppBar(title: 'Cue cards'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editDeck(),
        icon: const Icon(Icons.add),
        label: const Text('New deck'),
      ),
      body: decks == null
          ? const Center(child: CircularProgressIndicator())
          : decks.isEmpty
              ? const EmptyState(
                  title: 'No decks yet',
                  subtitle: 'Make a deck for a topic, then add question/answer cards.')
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(AppSpace.l, AppSpace.s, AppSpace.l, 100),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300,
                    mainAxisSpacing: AppSpace.m,
                    crossAxisSpacing: AppSpace.m,
                    childAspectRatio: 1.35,
                  ),
                  itemCount: decks.length,
                  itemBuilder: (context, i) => _DeckCard(
                    deck: decks[i],
                    onTap: () => _open(decks[i]),
                    onStudy: () => _study(decks[i]),
                    onLongPress: () => _options(decks[i]),
                  ),
                ),
    );
  }
}

class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.deck,
    required this.onTap,
    required this.onStudy,
    required this.onLongPress,
  });
  final Deck deck;
  final VoidCallback onTap;
  final VoidCallback onStudy;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(deck.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              if (deck.moduleName != null)
                ModuleTag(name: deck.moduleName!, color: deck.moduleColor ?? 0xFF8A8797),
              const Spacer(),
              Row(children: [
                Expanded(
                  child: Text(
                    '${deck.cardCount} cards'
                    '${deck.dueCount > 0 ? ' · ${deck.dueCount} to study' : ''}',
                    style: t.bodySmall?.copyWith(color: AppPalette.muted),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: deck.cardCount == 0 ? null : onStudy,
                  child: const Text('Study'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Returns (name, moduleId) or null.
Future<(String, int?)?> showDeckDialog(BuildContext context, List<Module> modules, Deck? deck) {
  final name = TextEditingController(text: deck?.name);
  int? moduleId = deck?.moduleId;
  return showDialog<(String, int?)>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(deck == null ? 'New deck' : 'Edit deck'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Deck name', hintText: 'e.g. Week 3 definitions'),
          ),
          const SizedBox(height: AppSpace.m),
          ModulePicker(modules: modules, value: moduleId, onChanged: (v) => moduleId = v),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final n = name.text.trim();
            if (n.isEmpty) return;
            Navigator.pop(context, (n, moduleId));
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
