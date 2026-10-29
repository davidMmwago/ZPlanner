// GENERATED from her ghost drawings (see ghost.py). Coordinates are in a
// 110 x 180 box; the heart pose reaches up to y = -8.
import 'dart:ui';

class GhostPaths {
  static const Offset eye = Offset(72.0, 50.0);
  static const double eyeRadius = 2.8;

  static Path body() {
    final p = Path()
      ..moveTo(16.0, 164.0)
      ..cubicTo(15.0, 125.0, 15.0, 90.0, 16.0, 68.0)
      ..cubicTo(16.0, 42.0, 33.0, 26.0, 54.0, 26.0)
      ..cubicTo(76.0, 26.0, 91.0, 41.0, 91.0, 58.0)
      ..cubicTo(91.0, 72.0, 84.0, 80.0, 74.0, 82.0)
      ..cubicTo(72.0, 105.0, 73.0, 135.0, 76.0, 160.0);
    return p;
  }
  static Path details() {
    final p = Path()
      ..moveTo(74.0, 82.0)
      ..quadraticBezierTo(65.0, 84.0, 57.0, 79.0)
      ..moveTo(47.0, 56.0)
      ..lineTo(45.5, 63.0)
      ..moveTo(51.5, 56.0)
      ..lineTo(50.0, 63.0)
      ..moveTo(56.0, 56.0)
      ..lineTo(54.5, 63.0);
    return p;
  }
  static Path curl() {
    final p = Path()
      ..moveTo(53.0, 26.0)
      ..cubicTo(50.0, 21.0, 57.0, 20.0, 55.0, 15.0)
      ..cubicTo(54.0, 12.0, 58.0, 11.0, 59.0, 13.0);
    return p;
  }
  static Path poseIdle() {
    final p = Path()
      ..moveTo(74.0, 104.0)
      ..quadraticBezierTo(80.0, 103.0, 87.0, 100.0)
      ..moveTo(46.0, 101.0)
      ..quadraticBezierTo(45.5, 110.0, 44.0, 119.0);
    return p;
  }
  static Path poseFlower() {
    final p = Path()
      ..moveTo(73.0, 100.0)
      ..lineTo(98.0, 98.0)
      ..moveTo(42.0, 112.0)
      ..lineTo(97.0, 109.0)
      ..moveTo(99.0, 122.0)
      ..quadraticBezierTo(95.0, 100.0, 98.0, 76.0)
      ..moveTo(98.0, 76.0)
      ..cubicTo(90.0, 74.0, 88.0, 63.0, 95.0, 60.0)
      ..cubicTo(97.0, 66.0, 98.0, 71.0, 98.0, 76.0)
      ..moveTo(98.0, 76.0)
      ..cubicTo(97.0, 68.0, 100.0, 58.0, 105.0, 57.0)
      ..cubicTo(107.0, 65.0, 103.0, 72.0, 98.0, 76.0)
      ..moveTo(98.0, 76.0)
      ..cubicTo(103.0, 71.0, 110.0, 69.0, 112.0, 73.0)
      ..cubicTo(110.0, 78.0, 104.0, 79.0, 98.0, 76.0);
    return p;
  }
  static Path poseHeart() {
    final p = Path()
      ..moveTo(40.0, 112.0)
      ..cubicTo(16.0, 96.0, 0.0, 52.0, 18.0, 24.0)
      ..cubicTo(28.0, 8.0, 42.0, 4.0, 52.0, 6.0)
      ..moveTo(74.0, 116.0)
      ..cubicTo(96.0, 104.0, 110.0, 60.0, 96.0, 26.0)
      ..cubicTo(90.0, 10.0, 72.0, 4.0, 58.0, 6.0)
      ..moveTo(55.0, 8.0)
      ..cubicTo(49.0, 2.0, 45.0, -4.0, 50.0, -7.0)
      ..cubicTo(53.0, -8.0, 55.0, -5.0, 55.0, -3.0)
      ..cubicTo(55.0, -5.0, 57.0, -8.0, 60.0, -7.0)
      ..cubicTo(65.0, -4.0, 61.0, 2.0, 55.0, 8.0);
    return p;
  }
}
