import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../data/app_files.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../google/google_api.dart';
import '../google/google_auth.dart';
import '../recording/record_button.dart';
import '../recording/recording_controller.dart';
import '../recording/recording_screen.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../workspace/workspace_screen.dart';

class ModuleScreen extends StatefulWidget {
  const ModuleScreen({super.key, required this.module});
  final Module module;

  @override
  State<ModuleScreen> createState() => _ModuleScreenState();
}

class _ModuleScreenState extends State<ModuleScreen> {
  List<StudyItem>? _items;
  String? _busy; // e.g. "Converting slides…"
  final _rec = RecordingController.instance;
  bool _wasRecording = false;

  static const _audioExt = {'.m4a', '.mp3', '.wav', '.aac', '.ogg'};

  @override
  void initState() {
    super.initState();
    _refresh();
    _rec.addListener(_onRecording);
  }

  @override
  void dispose() {
    _rec.removeListener(_onRecording);
    super.dispose();
  }

  // When a recording is saved, show it in the list.
  void _onRecording() {
    if (_wasRecording && !_rec.recording) {
      Future.delayed(const Duration(milliseconds: 400), _refresh);
    }
    _wasRecording = _rec.recording;
  }

  Future<void> _refresh() async {
    final items = await AppDb.instance.items(widget.module.id);
    if (mounted) setState(() => _items = items);
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Import: PDFs, PowerPoints (via Google) and audio ────────
  Future<void> _import() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'pptx', 'ppt', 'm4a', 'mp3', 'wav', 'aac', 'ogg'],
    );
    if (files.isEmpty || !mounted) return;
    for (final f in files) {
      final path = f.path;
      if (path == null) continue;
      final ext = p.extension(f.name).toLowerCase();
      final title = p.basenameWithoutExtension(f.name);
      try {
        if (ext == '.pdf') {
          setState(() => _busy = 'Importing $title…');
          final name = await AppFiles.importPdf(path);
          await AppDb.instance.addItem(
              moduleId: widget.module.id, type: ItemType.pdf, title: title, fileName: name);
        } else if (ext == '.pptx' || ext == '.ppt') {
          await _importPowerPoint(path, title);
        } else if (_audioExt.contains(ext)) {
          setState(() => _busy = 'Importing $title…');
          final name = await AppFiles.importAudio(path);
          await AppDb.instance.addItem(
              moduleId: widget.module.id, type: ItemType.audio, title: title, fileName: name, pageCount: 0);
        }
      } catch (e) {
        _snack('Couldn\'t import "$title": $e');
      }
    }
    if (mounted) setState(() => _busy = null);
    _refresh();
  }

  Future<void> _importPowerPoint(String path, String title) async {
    if (!GoogleAuth.instance.signedIn) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Connect Google first'),
          content: const Text(
            'PowerPoints are turned into PDFs using your Google Drive.\n\n'
            'Open Settings (in the side menu) and tap "Connect Google", then import again.\n\n'
            'Or save the slides as a PDF in another app and import that.',
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      return;
    }
    setState(() => _busy = 'Converting "$title" to PDF… (this can take a minute)');
    final name = AppFiles.uniqueName('$title.pdf');
    await GoogleApi.convertToPdf(File(path), title, AppFiles.docPath(name));
    await AppDb.instance.addItem(
        moduleId: widget.module.id, type: ItemType.pdf, title: title, fileName: name);
  }

  Future<void> _newNote() async {
    final d = DateTime.now();
    final title = await _askTitle(context, 'New note', 'Note ${d.day} ${monthsShort[d.month - 1]}');
    if (title == null) return;
    final id = await AppDb.instance.addItem(moduleId: widget.module.id, type: ItemType.note, title: title);
    final item = await AppDb.instance.item(id);
    if (item == null || !mounted) return;
    await _open(item);
  }

  Future<void> _open(StudyItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => item.type == ItemType.audio
            ? RecordingScreen(item: item)
            : WorkspaceScreen(item: item),
      ),
    );
    _refresh();
  }

  Future<void> _options(StudyItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () => Navigator.pop(context, 'rename'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete'),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') {
      final t = await _askTitle(context, 'Rename', item.title);
      if (t == null) return;
      await AppDb.instance.renameItem(item.id, t);
      _refresh();
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete "${item.title}"?'),
          content: Text(item.type == ItemType.audio
              ? 'The recording and its transcript will be deleted.'
              : 'Its drawings will be deleted too.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok == true) {
        await AppDb.instance.deleteItem(item);
        _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final color = Color(widget.module.color);
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpace.s),
          Flexible(child: Text(widget.module.name, overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          RecordButton(moduleId: widget.module.id),
          const SizedBox(width: AppSpace.s),
          FilledButton.tonalIcon(
            onPressed: _busy != null ? null : _import,
            icon: const Icon(Icons.upload_file),
            label: const Text('Import'),
          ),
          const SizedBox(width: AppSpace.s),
          FilledButton.icon(
            onPressed: _newNote,
            icon: const Icon(Icons.edit_note),
            label: const Text('New note'),
          ),
          const SizedBox(width: AppSpace.m),
        ],
        bottom: _busy == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(36),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.l, 0, AppSpace.l, AppSpace.s),
                  child: Row(children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: AppSpace.s),
                    Expanded(child: Text(_busy!, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ),
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(
                  child: Text(
                    'Nothing here yet.\nImport slides (PDF or PowerPoint), start a note, or record a lecture.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppPalette.muted),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(AppSpace.l),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    mainAxisSpacing: AppSpace.m,
                    crossAxisSpacing: AppSpace.m,
                    // Fixed card height so a 2-line title never overflows.
                    mainAxisExtent: 250,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _ItemCard(
                    item: items[i],
                    accent: color,
                    onTap: () => _open(items[i]),
                    onLongPress: () => _options(items[i]),
                  ),
                ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.accent,
    required this.onTap,
    required this.onLongPress,
  });
  final StudyItem item;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final (icon, kind) = switch (item.type) {
      ItemType.pdf => (Icons.picture_as_pdf_outlined, 'PDF'),
      ItemType.note => (Icons.sticky_note_2_outlined, 'Note'),
      ItemType.audio => (Icons.graphic_eq, item.pageCount > 0 ? minutesText((item.pageCount / 60).ceil()) : 'Audio'),
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: accent.withValues(alpha: 0.12),
                alignment: Alignment.center,
                child: Icon(icon, size: 48, color: accent),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$kind · ${_friendlyDate(item.updated)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _friendlyDate(DateTime d) {
  final now = DateTime.now();
  if (sameDay(d, now)) return 'Today ${hhmm(d)}';
  return '${d.day} ${monthsShort[d.month - 1]}';
}

Future<String?> _askTitle(BuildContext context, String heading, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(heading),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: (v) => Navigator.pop(context, v.trim().isEmpty ? null : v.trim()),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final v = ctrl.text.trim();
            Navigator.pop(context, v.isEmpty ? null : v);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
