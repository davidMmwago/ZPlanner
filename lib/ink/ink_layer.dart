import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'ink_controller.dart';
import 'stroke.dart';

/// A drawable page. Put a PDF image or paper background behind it.
///
/// Pen / S Pen / M-Pen draws. Fingers scroll (unless "finger draws" is on).
/// The pen's eraser end or side button erases. With the select tool the pen
/// draws a lasso around handwriting.
class InkLayer extends StatefulWidget {
  const InkLayer({
    super.key,
    required this.controller,
    required this.page,
    required this.width,
    required this.height,
    this.background,
  });

  final InkController controller;
  final int page;
  final double width;
  final double height;
  final Widget? background;

  @override
  State<InkLayer> createState() => _InkLayerState();
}

enum _Mode { draw, erase, lasso }

class _InkLayerState extends State<InkLayer> {
  int? _pointer;
  List<Offset>? _points; // stroke being drawn, or the lasso
  List<int> _times = []; // ms since the stroke started, per point
  int _startMs = 0;
  Duration _t0 = Duration.zero;
  _Mode _mode = _Mode.draw;
  List<Stroke> _erased = [];
  List<InkText> _erasedText = [];
  Offset? _cursor;
  final _live = ValueNotifier<int>(0);

  InkController get c => widget.controller;

  @override
  void dispose() {
    _live.dispose();
    super.dispose();
  }

  bool _accepts(PointerEvent e) {
    switch (e.kind) {
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
      case PointerDeviceKind.mouse: // emulator testing
        return true;
      case PointerDeviceKind.touch:
        if (!c.fingerDraws) return false;
        // Palm filter: big contact areas are palms, not fingertips/stylus tips.
        return c.palmRadius <= 0 || e.radiusMajor <= c.palmRadius;
      default:
        return false;
    }
  }

  _Mode _modeFor(PointerEvent e) {
    if (c.tool == InkTool.eraser ||
        e.kind == PointerDeviceKind.invertedStylus ||
        (e.buttons & kPrimaryStylusButton) != 0) {
      return _Mode.erase;
    }
    if (c.tool == InkTool.select) return _Mode.lasso;
    return _Mode.draw;
  }

  Offset _norm(Offset local) => local / widget.width;

  void _down(PointerDownEvent e) {
    final accepted = _pointer == null && _accepts(e);
    if (c.showPointerInfo.value) {
      c.pointerInfo.value = 'kind: ${e.kind.name}   '
          'size: ${e.radiusMajor.toStringAsFixed(1)}   '
          'pressure: ${e.pressure.toStringAsFixed(2)}   '
          '${accepted ? 'DRAWS' : 'ignored'}';
    }
    if (!accepted) return;
    _pointer = e.pointer;
    c.penActive.value = true;
    _mode = _modeFor(e);
    final p = _norm(e.localPosition);
    switch (_mode) {
      case _Mode.erase:
        final (s, t) = c.eraseAt(widget.page, p);
        _erased = [...s];
        _erasedText = [...t];
        _cursor = p;
      case _Mode.lasso:
        c.clearSelection();
        _points = [p];
      case _Mode.draw:
        c.clearSelection();
        _points = [p];
        _times = [0];
        _startMs = DateTime.now().millisecondsSinceEpoch;
        _t0 = e.timeStamp;
    }
    _live.value++;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final p = _norm(e.localPosition);
    if (_mode == _Mode.erase) {
      final (s, t) = c.eraseAt(widget.page, p);
      _erased.addAll(s);
      _erasedText.addAll(t);
      _cursor = p;
    } else {
      final pts = _points!;
      // Skip tiny movements to keep strokes light on slower tablets.
      if ((pts.last - p).distanceSquared > 3.6e-7) {
        pts.add(p);
        if (_mode == _Mode.draw) _times.add((e.timeStamp - _t0).inMilliseconds);
      }
    }
    _live.value++;
  }

  void _finish(PointerEvent e, {required bool cancelled}) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    c.penActive.value = false;
    switch (_mode) {
      case _Mode.erase:
        c.commitErase(widget.page, _erased, _erasedText);
        _erased = [];
        _erasedText = [];
        _cursor = null;
      case _Mode.lasso:
        if (!cancelled && _points != null) c.selectWithLasso(widget.page, _points!);
      case _Mode.draw:
        if (_points != null && !cancelled) {
          c.addStroke(
            widget.page,
            c.newStroke(_points!, startMs: _startMs, times: List.of(_times)),
          );
        }
    }
    _points = null;
    _live.value++;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: (e) => _finish(e, cancelled: false),
        onPointerCancel: (e) => _finish(e, cancelled: true),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.background != null) widget.background!,
            RepaintBoundary(
              child: CustomPaint(
                isComplex: true,
                painter: _StrokesPainter(c, widget.page, widget.width),
              ),
            ),
            CustomPaint(painter: _LivePainter(this)),
          ],
        ),
      ),
    );
  }
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter(this.c, this.page, this.scale) : super(repaint: c.rev(page));
  final InkController c;
  final int page;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final strokes = c.strokes(page);
    final sel = c.selection.value;
    final selected = (sel != null && sel.page == page) ? sel.strokes.toSet() : const <Stroke>{};

    // Highlighters first so they sit underneath handwriting.
    for (final s in strokes) {
      if (s.tool == InkTool.highlighter) paintStroke(canvas, s, scale);
    }
    for (final s in strokes) {
      if (s.tool == InkTool.highlighter) continue;
      if (selected.contains(s)) {
        // Soft glow behind selected strokes.
        paintStroke(
          canvas,
          Stroke(tool: s.tool, color: 0x553D7BFF, width: s.width + 0.006, points: s.points),
          scale,
        );
      }
      paintStroke(canvas, s, scale);
    }

    // Typed text boxes.
    for (final t in c.texts(page)) {
      final tp = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(color: Color(t.color), fontSize: t.fontSize * scale, height: 1.3),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: t.width * scale);
      tp.paint(canvas, t.pos * scale);
    }

    // Dashed-looking box around the selection.
    if (sel != null && sel.page == page) {
      final r = Rect.fromLTRB(
        sel.bounds.left * scale - 6,
        sel.bounds.top * scale - 6,
        sel.bounds.right * scale + 6,
        sel.bounds.bottom * scale + 6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF3D7BFF),
      );
    }
  }

  @override
  bool shouldRepaint(_StrokesPainter old) =>
      old.scale != scale || old.page != page || old.c != c;
}

class _LivePainter extends CustomPainter {
  _LivePainter(this.s) : super(repaint: s._live);
  final _InkLayerState s;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = s.widget.width;
    final pts = s._points;
    if (pts != null) {
      if (s._mode == _Mode.lasso) {
        final path = Path()..moveTo(pts.first.dx * scale, pts.first.dy * scale);
        for (final p in pts.skip(1)) {
          path.lineTo(p.dx * scale, p.dy * scale);
        }
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xFF3D7BFF),
        );
      } else {
        paintStroke(canvas, s.c.newStroke(pts), scale);
      }
    }
    final cur = s._cursor;
    if (cur != null) {
      canvas.drawCircle(
        cur * scale,
        s.c.eraserRadius * scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0x88000000),
      );
    }
  }

  @override
  bool shouldRepaint(_LivePainter old) => true;
}
