import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../recording/record_button.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'doc_pane.dart';

enum SplitMode { sideBySide, floating }

/// Opens a PDF or note. A second one can be opened beside it (split) or in a
/// floating window on top — e.g. lecture slides next to her notes.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, required this.item});
  final StudyItem item;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  late StudyItem _primary = widget.item;
  StudyItem? _secondary;
  SplitMode _mode = SplitMode.sideBySide;
  double _ratio = 0.5;
  Offset _winPos = const Offset(24, 24);
  Size _winSize = const Size(440, 560);

  /// One key per open item, so a pane keeps its pages and drawings when it
  /// moves between split view, the floating window, or swaps sides.
  final Map<int, GlobalKey> _keys = {};

  Widget _pane(StudyItem i) =>
      DocPane(key: _keys.putIfAbsent(i.id, () => GlobalKey()), item: i);

  Future<void> _openBeside([SplitMode? mode]) async {
    final picked = await pickDocument(
      context,
      exclude: {_primary.id, if (_secondary != null) _secondary!.id},
      preferModuleId: _primary.moduleId,
    );
    if (picked == null) return;
    setState(() {
      if (_secondary != null) _keys.remove(_secondary!.id);
      _secondary = picked;
      if (mode != null) _mode = mode;
    });
  }

  void _swap() => setState(() {
        final s = _secondary!;
        _secondary = _primary;
        _primary = s;
      });

  void _closeSecondary() => setState(() {
        _keys.remove(_secondary!.id);
        _secondary = null;
      });

  void _toggleMode() => setState(() =>
      _mode = _mode == SplitMode.sideBySide ? SplitMode.floating : SplitMode.sideBySide);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_primary.title, overflow: TextOverflow.ellipsis),
        actions: [
          RecordButton(moduleId: _primary.moduleId),
          const SizedBox(width: AppSpace.s),
          if (_secondary == null)
            PopupMenuButton<SplitMode>(
              tooltip: 'Open another document',
              icon: const Icon(Icons.vertical_split_outlined),
              onSelected: _openBeside,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: SplitMode.sideBySide,
                  child: ListTile(leading: Icon(Icons.vertical_split), title: Text('Open side by side')),
                ),
                PopupMenuItem(
                  value: SplitMode.floating,
                  child: ListTile(leading: Icon(Icons.picture_in_picture_alt), title: Text('Open in a window')),
                ),
              ],
            ),
          const SizedBox(width: AppSpace.s),
        ],
      ),
      body: LayoutBuilder(builder: (context, cons) {
        final sec = _secondary;
        if (sec == null) return _pane(_primary);
        return _mode == SplitMode.sideBySide ? _split(cons, sec) : _floating(cons, sec);
      }),
    );
  }

  // ── Side by side ───────────────────────────────────────────
  Widget _split(BoxConstraints cons, StudyItem sec) {
    // Landscape: left/right. Portrait: top/bottom.
    final horizontal = cons.maxWidth >= cons.maxHeight;
    final total = horizontal ? cons.maxWidth : cons.maxHeight;
    const handle = 14.0;
    final first = (total - handle) * _ratio;

    final divider = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => setState(() {
        final delta = horizontal ? d.delta.dx : d.delta.dy;
        _ratio = (_ratio + delta / total).clamp(0.25, 0.75).toDouble();
      }),
      child: Container(
        width: horizontal ? handle : double.infinity,
        height: horizontal ? double.infinity : handle,
        color: const Color(0x0F000000),
        alignment: Alignment.center,
        child: Container(
          width: horizontal ? 4 : 40,
          height: horizontal ? 40 : 4,
          decoration: BoxDecoration(color: AppPalette.muted, borderRadius: BorderRadius.circular(2)),
        ),
      ),
    );

    final second = Column(children: [
      _PaneHeader(
        item: sec,
        onSwap: _swap,
        onMode: _toggleMode,
        modeIcon: Icons.picture_in_picture_alt,
        modeTip: 'Pop out into a window',
        onClose: _closeSecondary,
      ),
      Expanded(child: _pane(sec)),
    ]);

    return horizontal
        ? Row(children: [
            SizedBox(width: first, child: _pane(_primary)),
            divider,
            Expanded(child: second),
          ])
        : Column(children: [
            SizedBox(height: first, child: _pane(_primary)),
            divider,
            Expanded(child: second),
          ]);
  }

  // ── Floating window ────────────────────────────────────────
  Widget _floating(BoxConstraints cons, StudyItem sec) {
    final w = _winSize.width.clamp(280.0, cons.maxWidth).toDouble();
    final h = _winSize.height.clamp(300.0, cons.maxHeight).toDouble();
    final x = _winPos.dx.clamp(0.0, cons.maxWidth - w).toDouble();
    final y = _winPos.dy.clamp(0.0, cons.maxHeight - h).toDouble();

    return Stack(children: [
      Positioned.fill(child: _pane(_primary)),
      Positioned(
        left: x,
        top: y,
        width: w,
        height: h,
        child: Material(
          elevation: 10,
          shadowColor: Colors.black45,
          borderRadius: BorderRadius.circular(AppShape.radius),
          clipBehavior: Clip.antiAlias,
          color: AppPalette.background,
          child: Stack(children: [
            Column(children: [
              // Drag the header to move the window.
              GestureDetector(
                onPanUpdate: (d) => setState(() => _winPos = Offset(x, y) + d.delta),
                child: _PaneHeader(
                  item: sec,
                  onSwap: _swap,
                  onMode: _toggleMode,
                  modeIcon: Icons.vertical_split,
                  modeTip: 'Dock side by side',
                  onClose: _closeSecondary,
                  showGrip: true,
                ),
              ),
              Expanded(child: _pane(sec)),
            ]),
            // Drag the bottom-right corner to resize.
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() => _winSize = Size(w, h) + d.delta),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.bottomRight,
                  padding: const EdgeInsets.all(6),
                  child: const Icon(Icons.open_in_full, size: 18, color: AppPalette.muted),
                ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({
    required this.item,
    required this.onSwap,
    required this.onMode,
    required this.modeIcon,
    required this.modeTip,
    required this.onClose,
    this.showGrip = false,
  });
  final StudyItem item;
  final VoidCallback onSwap;
  final VoidCallback onMode;
  final IconData modeIcon;
  final String modeTip;
  final VoidCallback onClose;
  final bool showGrip;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: AppPalette.surface,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s),
      child: Row(children: [
        if (showGrip) const Icon(Icons.drag_indicator, color: AppPalette.muted, size: 20),
        const SizedBox(width: 4),
        Icon(
          item.type == ItemType.pdf ? Icons.picture_as_pdf_outlined : Icons.sticky_note_2_outlined,
          size: 18,
          color: AppPalette.muted,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(item.title,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        IconButton(tooltip: 'Swap sides', onPressed: onSwap, icon: const Icon(Icons.swap_horiz)),
        IconButton(tooltip: modeTip, onPressed: onMode, icon: Icon(modeIcon)),
        IconButton(tooltip: 'Close', onPressed: onClose, icon: const Icon(Icons.close)),
      ]),
    );
  }
}

/// Bottom sheet listing every PDF and note (this module's first).
Future<StudyItem?> pickDocument(
  BuildContext context, {
  Set<int> exclude = const {},
  int? preferModuleId,
}) async {
  final all = (await AppDb.instance.allDocs()).where((d) => !exclude.contains(d.item.id)).toList();
  all.sort((a, b) {
    final ap = a.item.moduleId == preferModuleId ? 0 : 1;
    final bp = b.item.moduleId == preferModuleId ? 0 : 1;
    return ap != bp ? ap - bp : 0;
  });
  if (!context.mounted) return null;
  return showModalBottomSheet<StudyItem>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.all(AppSpace.m),
            child: Text('Open beside', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: all.isEmpty
                ? const Center(
                    child: Text('No other PDFs or notes yet.', style: TextStyle(color: AppPalette.muted)))
                : ListView.builder(
                    itemCount: all.length,
                    itemBuilder: (context, i) {
                      final d = all[i];
                      final showHeader = i == 0 || all[i - 1].item.moduleId != d.item.moduleId;
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (showHeader)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(AppSpace.m, AppSpace.m, AppSpace.m, 4),
                            child: ModuleTag(name: d.moduleName, color: d.moduleColor),
                          ),
                        ListTile(
                          leading: Icon(d.item.type == ItemType.pdf
                              ? Icons.picture_as_pdf_outlined
                              : Icons.sticky_note_2_outlined),
                          title: Text(d.item.title),
                          onTap: () => Navigator.pop(context, d.item),
                        ),
                      ]);
                    },
                  ),
          ),
        ]),
      ),
    ),
  );
}
