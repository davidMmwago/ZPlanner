import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'module_screen.dart';

class ModulesScreen extends StatefulWidget {
  const ModulesScreen({super.key});

  @override
  State<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends State<ModulesScreen> {
  List<Module>? _modules;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final m = await AppDb.instance.modules();
    if (mounted) setState(() => _modules = m);
  }

  Future<void> _create() async {
    final result = await showModuleDialog(context);
    if (result == null) return;
    await AppDb.instance.addModule(result.name, result.color);
    _refresh();
  }

  Future<void> _options(Module m) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename / change colour'),
            onTap: () => Navigator.pop(context, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete module'),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') {
      final r = await showModuleDialog(context, initialName: m.name, initialColor: m.color);
      if (r == null) return;
      await AppDb.instance.updateModule(m.id, name: r.name, color: r.color);
      _refresh();
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete "${m.name}"?'),
          content: const Text('This deletes every PDF, note and drawing in it. This can\'t be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok == true) {
        await AppDb.instance.deleteModule(m.id);
        _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final modules = _modules;
    return Scaffold(
      appBar: AppBar(
        title: Text('Modules', style: Theme.of(context).textTheme.headlineMedium),
        toolbarHeight: 72,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New module'),
      ),
      body: modules == null
          ? const Center(child: CircularProgressIndicator())
          : modules.isEmpty
              ? const EmptyState(
                  title: 'No modules yet',
                  subtitle: 'Tap "New module" to add one for each subject.')
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(AppSpace.l, AppSpace.s, AppSpace.l, 100),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280,
                    mainAxisSpacing: AppSpace.m,
                    crossAxisSpacing: AppSpace.m,
                    mainAxisExtent: 190,
                  ),
                  itemCount: modules.length,
                  itemBuilder: (context, i) {
                    final m = modules[i];
                    return _ModuleCard(
                      module: m,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ModuleScreen(module: m)),
                        );
                        _refresh();
                      },
                      onLongPress: () => _options(m),
                    );
                  },
                ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module, required this.onTap, required this.onLongPress});
  final Module module;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final color = Color(module.color);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 56, color: color.withValues(alpha: 0.85)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      module.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${module.itemCount} ${module.itemCount == 1 ? 'item' : 'items'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Create / edit dialog ─────────────────────────────────────
class ModuleDialogResult {
  final String name;
  final int color;
  ModuleDialogResult(this.name, this.color);
}

Future<ModuleDialogResult?> showModuleDialog(
  BuildContext context, {
  String? initialName,
  int? initialColor,
}) {
  final nameCtrl = TextEditingController(text: initialName);
  var color = initialColor ?? AppPalette.moduleColors.first.toARGB32();
  return showDialog<ModuleDialogResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text(initialName == null ? 'New module' : 'Edit module'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Module name', hintText: 'e.g. INFS4001'),
              ),
              const SizedBox(height: AppSpace.m),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in AppPalette.moduleColors)
                    GestureDetector(
                      onTap: () => setLocal(() => color = c.toARGB32()),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == c.toARGB32() ? AppPalette.ink : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context, ModuleDialogResult(name, color));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
