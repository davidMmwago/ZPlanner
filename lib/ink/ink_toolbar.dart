import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'handwriting.dart';
import 'ink_controller.dart';
import 'stroke.dart';

/// Floating pill with pen / highlighter / eraser, colours, sizes, undo/redo.
class InkToolbar extends StatelessWidget {
  const InkToolbar({super.key, required this.controller});
  final InkController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final isHl = c.tool == InkTool.highlighter;
        final colors = isHl ? AppPalette.highlighterColors : AppPalette.penColors;
        final current = isHl ? c.highlighterColor : c.penColor;
        final widths = isHl ? InkController.highlighterWidths : InkController.penWidths;
        final currentWidth = isHl ? c.highlighterWidth : c.penWidth;

        final pill = Material(
          color: AppPalette.surface,
          elevation: 3,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _toolBtn(context, Icons.edit, InkTool.pen, 'Pen'),
                  _toolBtn(context, Icons.border_color, InkTool.highlighter, 'Highlighter'),
                  _toolBtn(context, Icons.auto_fix_normal, InkTool.eraser, 'Eraser'),
                  _toolBtn(context, Icons.highlight_alt, InkTool.select,
                      'Select (lasso handwriting to turn it into text)'),
                  _divider(),
                  if (c.tool == InkTool.pen || c.tool == InkTool.highlighter) ...[
                    for (final col in colors)
                      _ColorDot(
                        color: col,
                        selected: col.toARGB32() == current.toARGB32(),
                        onTap: () => c.setColor(col),
                      ),
                    _divider(),
                    for (var i = 0; i < widths.length; i++)
                      _SizeDot(
                        size: 6.0 + i * 5,
                        selected: widths[i] == currentWidth,
                        color: scheme.primary,
                        onTap: () => c.setWidth(widths[i]),
                      ),
                    _divider(),
                  ],
                  IconButton(
                    tooltip: 'Undo',
                    icon: const Icon(Icons.undo),
                    onPressed: c.canUndo ? c.undo : null,
                  ),
                  IconButton(
                    tooltip: 'Redo',
                    icon: const Icon(Icons.redo),
                    onPressed: c.canRedo ? c.redo : null,
                  ),
                  _divider(),
                  GestureDetector(
                    // Hidden: long-press toggles the pen check read-out.
                    onLongPress: () =>
                        c.showPointerInfo.value = !c.showPointerInfo.value,
                    child: IconButton(
                      isSelected: c.fingerDraws,
                      icon: const Icon(Icons.pan_tool_outlined),
                      selectedIcon: const Icon(Icons.gesture),
                      onPressed: c.toggleFingerDraws,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            pill,
            ValueListenableBuilder<InkSelection?>(
              valueListenable: c.selection,
              builder: (context, sel, _) => sel == null
                  ? (c.tool == InkTool.select
                      ? const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: _Hint('Draw a loop around your handwriting'),
                        )
                      : const SizedBox.shrink())
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _SelectionBar(controller: c, selection: sel),
                    ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: c.showPointerInfo,
              builder: (context, show, _) => !show
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _PointerInfoBadge(controller: c),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _toolBtn(BuildContext context, IconData icon, InkTool t, String tip) {
    return IconButton(
      tooltip: tip,
      isSelected: controller.tool == t,
      style: IconButton.styleFrom(
        backgroundColor: controller.tool == t
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
      ),
      icon: Icon(icon),
      onPressed: () => controller.setTool(t),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: Colors.black12,
      );
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppPalette.ink : Colors.black12,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

class _SizeDot extends StatelessWidget {
  const _SizeDot({
    required this.size,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final double size;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? color.withValues(alpha: 0.15) : null,
        ),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: selected ? color : AppPalette.muted,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _PointerInfoBadge extends StatelessWidget {
  const _PointerInfoBadge({required this.controller});
  final InkController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xDD1F1D2B),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: controller.pointerInfo,
              builder: (context, info, _) => Text(
                info,
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            const Text('palm filter',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            StatefulBuilder(
              builder: (context, setLocal) => SizedBox(
                width: 160,
                child: Slider(
                  value: controller.palmRadius,
                  min: 0,
                  max: 40,
                  divisions: 40,
                  label: controller.palmRadius == 0
                      ? 'off'
                      : controller.palmRadius.toStringAsFixed(0),
                  onChanged: (v) => setLocal(() => controller.palmRadius = v),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xDD1F1D2B),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
      );
}

/// Shown under the toolbar while handwriting is selected.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.controller, required this.selection});
  final InkController controller;
  final InkSelection selection;

  @override
  Widget build(BuildContext context) {
    final n = selection.strokes.length;
    return Material(
      color: AppPalette.surface,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('$n stroke${n == 1 ? '' : 's'}', style: const TextStyle(color: AppPalette.muted)),
          ),
          FilledButton.icon(
            onPressed: () => convertSelectionToText(context, controller),
            icon: const Icon(Icons.text_fields, size: 18),
            label: const Text('To text'),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Delete',
            onPressed: controller.deleteSelection,
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Done',
            onPressed: controller.clearSelection,
            icon: const Icon(Icons.close),
          ),
        ]),
      ),
    );
  }
}

/// Reads the selected handwriting and lets her copy it or swap it for text.
Future<void> convertSelectionToText(BuildContext context, InkController c) async {
  final sel = c.selection.value;
  if (sel == null) return;
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
        SizedBox(width: 16),
        Expanded(child: Text('Reading your handwriting…\n(the first time downloads ~20 MB)')),
      ]),
    ),
  );

  String text = '';
  var lines = 1;
  var alternatives = <String>[];
  String? error;
  try {
    if (!await Handwriting.ensureModel()) {
      error = 'Couldn\'t download the handwriting model. Check the internet connection and try again.';
    } else {
      final r = await Handwriting.recognize(sel.strokes);
      text = r.text;
      lines = r.lineCount;
      alternatives = r.alternatives;
    }
  } catch (e) {
    error = 'Handwriting recognition failed: $e';
  }
  navigator.pop(); // progress dialog

  if (error != null) {
    messenger.showSnackBar(SnackBar(content: Text(error)));
    return;
  }
  if (text.trim().isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t read any words there.')));
    return;
  }
  if (!context.mounted) return;

  final ctrl = TextEditingController(text: text);
  final action = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Your handwriting as text'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: ctrl,
            minLines: 2,
            maxLines: 10,
            decoration: const InputDecoration(helperText: 'Fix anything it misread before using it.'),
          ),
          if (alternatives.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Or did you mean:', style: TextStyle(color: AppPalette.muted, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final a in alternatives)
                ActionChip(label: Text(a), onPressed: () => ctrl.text = a),
            ]),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, 'copy'), child: const Text('Copy')),
        FilledButton(
          onPressed: () => Navigator.pop(context, 'replace'),
          child: const Text('Replace handwriting'),
        ),
      ],
    ),
  );
  if (action == 'copy') {
    await Clipboard.setData(ClipboardData(text: ctrl.text));
    messenger.showSnackBar(const SnackBar(content: Text('Copied')));
  } else if (action == 'replace') {
    c.replaceSelectionWithText(ctrl.text, lineCount: lines);
  }
}
