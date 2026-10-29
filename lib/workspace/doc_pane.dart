import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/app_files.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../ink/ink_controller.dart';
import '../ink/ink_toolbar.dart';
import '../ink/paged_ink_view.dart';
import '../theme/app_theme.dart';

/// One open PDF or note: its pages, drawings and drawing toolbar.
/// Used on its own, side by side, or inside a floating window.
class DocPane extends StatefulWidget {
  const DocPane({super.key, required this.item});
  final StudyItem item;

  @override
  State<DocPane> createState() => _DocPaneState();
}

class _DocPaneState extends State<DocPane> {
  static const double a4Aspect = 1.4142;

  PdfDocument? _doc;
  InkController? _ink;
  String? _error;
  late int _notePages = widget.item.pageCount < 1 ? 1 : widget.item.pageCount;

  bool get _isPdf => widget.item.type == ItemType.pdf;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      PdfDocument? doc;
      if (_isPdf) doc = await PdfDocument.openFile(AppFiles.docPath(widget.item.fileName!));
      final ink = await InkController.load(widget.item.id);
      if (!mounted) {
        doc?.dispose();
        ink.dispose();
        return;
      }
      setState(() {
        _doc = doc;
        _ink = ink;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    final ink = _ink;
    if (ink != null) ink.saveNow().whenComplete(ink.dispose);
    _doc?.dispose();
    super.dispose();
  }

  Future<void> _addPage() async {
    setState(() => _notePages++);
    await AppDb.instance.setPageCount(widget.item.id, _notePages);
  }

  @override
  Widget build(BuildContext context) {
    final ink = _ink;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.l),
          child: Text('Could not open this file.\n$_error', textAlign: TextAlign.center),
        ),
      );
    }
    if (ink == null || (_isPdf && _doc == null)) {
      return const Center(child: CircularProgressIndicator());
    }
    final doc = _doc;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (doc != null)
          PagedInkView(
            controller: ink,
            pageCount: doc.pages.length,
            aspectOf: (i) => doc.pages[i].height / doc.pages[i].width,
            background: (context, i, w, h) => _PdfPageImage(page: doc.pages[i], width: w, height: h),
          )
        else
          PagedInkView(
            controller: ink,
            pageCount: _notePages,
            aspectOf: (_) => a4Aspect,
            background: (context, i, w, h) => CustomPaint(painter: _LinedPaperPainter()),
            footer: Center(
              child: FilledButton.tonalIcon(
                onPressed: _addPage,
                icon: const Icon(Icons.add),
                label: const Text('Add page'),
              ),
            ),
          ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Center(child: InkToolbar(controller: ink)),
        ),
      ],
    );
  }
}

/// Renders one PDF page to an image, sized for the screen.
/// Pages are rendered only when scrolled near, and freed when scrolled away.
class _PdfPageImage extends StatefulWidget {
  const _PdfPageImage({required this.page, required this.width, required this.height});
  final PdfPage page;
  final double width;
  final double height;

  @override
  State<_PdfPageImage> createState() => _PdfPageImageState();
}

class _PdfPageImageState extends State<_PdfPageImage> {
  ui.Image? _image;
  double? _requestedWidth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeRender();
  }

  @override
  void didUpdateWidget(_PdfPageImage old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page) _requestedWidth = null;
    _maybeRender();
  }

  void _maybeRender() {
    // Small width changes (e.g. dragging the split divider) don't re-render;
    // the existing image just scales until the change is big enough.
    final last = _requestedWidth;
    if (last != null && (last - widget.width).abs() < 60) return;
    _requestedWidth = widget.width;
    _render(widget.width);
  }

  Future<void> _render(double width) async {
    // Cap resolution so the older Kirin chip isn't overloaded.
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0).toDouble();
    final pw = math.min((width * dpr).round(), 2000);
    final ph = (pw * widget.page.height / widget.page.width).round();
    final pdfImage = await widget.page.render(
      width: pw,
      height: ph,
      fullWidth: pw.toDouble(),
      fullHeight: ph.toDouble(),
    );
    if (pdfImage == null) return;
    final img = await pdfImage.createImage();
    pdfImage.dispose();
    if (!mounted || _requestedWidth != width) {
      img.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = img;
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    return ColoredBox(
      color: Colors.white,
      child: img == null
          ? const Center(
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
          : RawImage(image: img, fit: BoxFit.fill),
    );
  }
}

class _LinedPaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppPalette.paper);
    final line = Paint()
      ..color = AppPalette.paperLine
      ..strokeWidth = 1;
    final gap = size.width * 0.035;
    for (var y = size.width * 0.1; y < size.height - gap; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final margin = Paint()
      ..color = AppPalette.paperMargin
      ..strokeWidth = 1.2;
    final x = size.width * 0.1;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), margin);
  }

  @override
  bool shouldRepaint(_LinedPaperPainter old) => false;
}
