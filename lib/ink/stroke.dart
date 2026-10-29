import 'dart:ui';

enum InkTool { pen, highlighter, eraser, select }

/// One pen/highlighter stroke.
///
/// Points are stored in "page units": x and y are divided by the page's
/// on-screen width, so drawings stay in place at any size or zoom.
class Stroke {
  final InkTool tool;
  final int color;

  /// Width as a fraction of page width.
  final double width;
  final List<Offset> points;

  /// When the stroke started (ms since epoch) and each point's time offset
  /// from that start (ms). Used by handwriting recognition; null for strokes
  /// drawn before this was recorded.
  final int? startMs;
  final List<int>? times;

  Rect? _bounds;

  Stroke({
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
    this.startMs,
    this.times,
  });

  Rect get bounds {
    if (_bounds != null) return _bounds!;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final o in points) {
      if (o.dx < minX) minX = o.dx;
      if (o.dy < minY) minY = o.dy;
      if (o.dx > maxX) maxX = o.dx;
      if (o.dy > maxY) maxY = o.dy;
    }
    return _bounds = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(width);
  }

  bool hitTest(Offset p, double radius) {
    if (!bounds.inflate(radius).contains(p)) return false;
    final r2 = (radius + width / 2) * (radius + width / 2);
    for (var i = 0; i < points.length; i++) {
      if ((points[i] - p).distanceSquared <= r2) return true;
      if (i > 0 && _segDist2(p, points[i - 1], points[i]) <= r2) return true;
    }
    return false;
  }

  static double _segDist2(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.distanceSquared;
    if (len2 == 0) return (p - a).distanceSquared;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
    t = t.clamp(0.0, 1.0).toDouble();
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distanceSquared;
  }

  // Compact JSON: coordinates stored as ints (x 100 000) to keep files small.
  Map<String, dynamic> toJson() => {
        't': tool.index,
        'c': color,
        'w': width,
        'p': [
          for (final o in points) ...[
            (o.dx * 100000).round(),
            (o.dy * 100000).round()
          ]
        ],
        if (startMs != null && times != null && times!.length == points.length) ...{
          's': startMs,
          'ts': times,
        },
      };

  factory Stroke.fromJson(Map<String, dynamic> j) {
    final raw = (j['p'] as List).cast<num>();
    final pts = <Offset>[
      for (var i = 0; i + 1 < raw.length; i += 2)
        Offset(raw[i] / 100000, raw[i + 1] / 100000)
    ];
    final ts = (j['ts'] as List?)?.cast<num>().map((n) => n.toInt()).toList();
    return Stroke(
      tool: InkTool.values[j['t'] as int],
      color: j['c'] as int,
      width: (j['w'] as num).toDouble(),
      points: pts,
      startMs: (j['s'] as num?)?.toInt(),
      times: (ts != null && ts.length == pts.length) ? ts : null,
    );
  }
}

/// Draws a stroke with smoothing (quadratic curves through midpoints).
void paintStroke(Canvas canvas, Stroke s, double scale) {
  final pts = s.points;
  if (pts.isEmpty) return;
  final paint = Paint()
    ..color = Color(s.color)
    ..strokeWidth = s.width * scale
    ..style = PaintingStyle.stroke
    ..strokeCap =
        s.tool == InkTool.highlighter ? StrokeCap.square : StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  if (pts.length == 1) {
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(pts.first * scale, s.width * scale / 2, paint);
    return;
  }

  final path = Path()..moveTo(pts[0].dx * scale, pts[0].dy * scale);
  for (var i = 1; i < pts.length - 1; i++) {
    final a = pts[i] * scale;
    final b = pts[i + 1] * scale;
    path.quadraticBezierTo(a.dx, a.dy, (a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  }
  path.lineTo(pts.last.dx * scale, pts.last.dy * scale);
  canvas.drawPath(path, paint);
}

/// Typed text placed on a page (e.g. converted handwriting).
/// Position, width and font size are in page units (fractions of page width).
class InkText {
  final Offset pos;
  final double width;
  final String text;
  final double fontSize;
  final int color;

  InkText({
    required this.pos,
    required this.width,
    required this.text,
    required this.fontSize,
    required this.color,
  });

  /// Rough bounds for erasing/hit-testing (height estimated from line count).
  Rect get bounds {
    final lines = text.split('\n').length;
    final charsPerLine = (width / (fontSize * 0.5)).clamp(1, 1000);
    final wrapped = text
        .split('\n')
        .fold<int>(0, (n, l) => n + (l.length / charsPerLine).ceil().clamp(1, 1000).toInt());
    final h = fontSize * 1.3 * (wrapped > lines ? wrapped : lines);
    return Rect.fromLTWH(pos.dx, pos.dy, width, h);
  }

  Map<String, dynamic> toJson() => {
        'x': pos.dx,
        'y': pos.dy,
        'w': width,
        's': text,
        'f': fontSize,
        'c': color,
      };

  factory InkText.fromJson(Map<String, dynamic> j) => InkText(
        pos: Offset((j['x'] as num).toDouble(), (j['y'] as num).toDouble()),
        width: (j['w'] as num).toDouble(),
        text: j['s'] as String,
        fontSize: (j['f'] as num).toDouble(),
        color: j['c'] as int,
      );
}
