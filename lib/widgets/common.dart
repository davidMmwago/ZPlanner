import 'package:flutter/material.dart';

import '../data/models.dart';
import '../mascot/ghost.dart';
import '../theme/app_theme.dart';

/// Big page title used by every section.
class SectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SectionAppBar({super.key, required this.title, this.actions});
  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) => AppBar(
        title: Text(title, style: Theme.of(context).textTheme.headlineMedium),
        toolbarHeight: 72,
        actions: actions,
      );
}

/// Friendly empty state with the ghost.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Ghost(height: 120, pose: GhostPose.idle),
          const SizedBox(height: AppSpace.m),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpace.xs),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppPalette.muted)),
        ]),
      ),
    );
  }
}

/// Small coloured dot + module name.
class ModuleTag extends StatelessWidget {
  const ModuleTag({super.key, required this.name, required this.color});
  final String name;
  final int color;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: Color(color), shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppPalette.muted, fontSize: 13)),
      ),
    ]);
  }
}

/// Dropdown for picking a module (or none).
class ModulePicker extends StatelessWidget {
  const ModulePicker({
    super.key,
    required this.modules,
    required this.value,
    required this.onChanged,
    this.label = 'Module',
  });
  final List<Module> modules;
  final int? value;
  final ValueChanged<int?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final safeValue = modules.any((m) => m.id == value) ? value : null;
    return DropdownButtonFormField<int?>(
      initialValue: safeValue,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('None')),
        for (final m in modules)
          DropdownMenuItem<int?>(
            value: m.id,
            child: ModuleTag(name: m.name, color: m.color),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

Future<bool> confirmDelete(BuildContext context, String what, {String? detail}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete $what?'),
      content: detail == null ? null : Text(detail),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
      ],
    ),
  );
  return ok == true;
}
