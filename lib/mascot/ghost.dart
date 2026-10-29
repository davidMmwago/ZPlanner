import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ghost_paths.dart';

/// Her ghost. idle = little wave arm, flower = offering a flower,
/// heart = arms up making a heart.
enum GhostPose { idle, flower, heart }

/// The floating ghost with its swirl underneath.
/// The ghost bobs up and down, the swirl slowly turns, and it blinks.
class Ghost extends StatefulWidget {
  const Ghost({
    super.key,
    this.pose = GhostPose.idle,
    this.height = 120,
    this.animate = true,
  });

  final GhostPose pose;
  final double height;
  final bool animate;

  /// Width / height of the drawing box.
  static const double aspect = _GhostPainter.boxW / _GhostPainter.boxH;

  @override
  State<Ghost> createState() => _GhostState();
}

class _GhostState extends State<Ghost> with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  Timer? _blinkTimer;
  bool _blink = false;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _float.repeat();
      _scheduleBlink();
    }
  }

  void _scheduleBlink() {
    _blinkTimer = Timer(Duration(milliseconds: 2500 + _rng.nextInt(4000)), () {
      if (!mounted) return;
      setState(() => _blink = true);
      _blinkTimer = Timer(const Duration(milliseconds: 140), () {
        if (!mounted) return;
        setState(() => _blink = false);
        _scheduleBlink();
      });
    });
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    return SizedBox(
      width: h * Ghost.aspect,
      height: h,
      child: AnimatedBuilder(
        animation: _float,
        builder: (context, _) => CustomPaint(
          painter: _GhostPainter(
            pose: widget.pose,
            t: _float.value,
            blink: _blink,
          ),
        ),
      ),
    );
  }
}

class _GhostPainter extends CustomPainter {
  _GhostPainter({required this.pose, required this.t, required this.blink});
  final GhostPose pose;
  final double t; // 0..1 animation phase
  final bool blink;

  // Drawing box in ghost_paths units: x 0..118, y -10..206
  static const double boxW = 118;
  static const double boxH = 216;
  static const double top = -10;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height / boxH;
    canvas.save();
    canvas.scale(s);
    canvas.translate(0, -top);

    final line = Paint()
      ..color = AppPalette.ghostLine
      ..style = PaintingStyle.stroke
      // Keep lines at least ~2px thick even when the ghost is drawn small.
      ..strokeWidth = math.max(2.6, 2.0 / s)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // ── Swirl on the ground (stays put, slowly turns) ──
    final bob = math.sin(t * 2 * math.pi); // -1..1
    canvas.drawPath(_spiral(phase: t * 2 * math.pi, squash: 1 - bob * 0.04), line);

    // ── Ghost (floats) ──
    canvas.save();
    canvas.translate(0, -4 - bob * 4);
    final body = GhostPaths.body(); // sides + head, open at the bottom
    _addHem(body, t * 2 * math.pi * 2); // rippling bottom edge
    body.close();
    canvas.drawPath(body, Paint()..color = AppPalette.ghostFill);
    canvas.drawPath(body, line);
    canvas.drawPath(GhostPaths.details(), line);
    if (pose != GhostPose.heart) canvas.drawPath(GhostPaths.curl(), line);
    switch (pose) {
      case GhostPose.idle:
        canvas.drawPath(GhostPaths.poseIdle(), line);
      case GhostPose.flower:
        canvas.drawPath(GhostPaths.poseFlower(), line);
      case GhostPose.heart:
        canvas.drawPath(GhostPaths.poseHeart(), line);
    }
    if (blink) {
      canvas.drawLine(
        GhostPaths.eye - const Offset(3, 0),
        GhostPaths.eye + const Offset(3, 0),
        line,
      );
    } else {
      canvas.drawCircle(GhostPaths.eye, GhostPaths.eyeRadius,
          Paint()..color = AppPalette.ghostLine);
    }
    canvas.restore();
    canvas.restore();
  }

  /// Wavy bottom edge from bottom-right (76,160) to bottom-left (16,164).
  /// The ends stay attached to the sides; the middle ripples.
  void _addHem(Path p, double phase) {
    const n = 36;
    for (var i = 1; i <= n; i++) {
      final u = i / n;
      final x = 76 + (16 - 76) * u;
      final base = 160 + (164 - 160) * u;
      final envelope = math.pow(math.sin(math.pi * u), 0.6).toDouble();
      final y = base + 3.2 * envelope * math.sin(2 * math.pi * 1.5 * u + phase);
      p.lineTo(x, y);
    }
  }

  /// Flat spiral under the ghost, like in her drawing.
  Path _spiral({required double phase, required double squash}) {
    const cx = 46.0, cy = 192.0, a = 50.0, b = 11.0;
    const turns = 2.1, inner = 0.14, n = 140;
    final start = -0.35 * math.pi + phase;
    final p = Path();
    for (var i = 0; i <= n; i++) {
      final u = i / n;
      final ang = start + u * turns * 2 * math.pi;
      final r = 1 - (1 - inner) * u;
      final x = cx + a * squash * r * math.cos(ang);
      final y = cy + b * r * math.sin(ang);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    return p;
  }

  @override
  bool shouldRepaint(_GhostPainter old) =>
      old.t != t || old.pose != pose || old.blink != blink;
}
