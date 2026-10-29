import 'dart:async';

import 'package:flutter/material.dart';

import '../data/kv.dart';
import '../theme/app_theme.dart';
import 'ghost.dart';
import 'messages.dart';

/// Lets any part of the app make the ghost speak:
///   Mascot.instance.say('Hello!', pose: GhostPose.heart);
class Mascot extends ChangeNotifier {
  Mascot._();
  static final Mascot instance = Mascot._();

  String? message;
  GhostPose pose = GhostPose.idle;
  Timer? _hide;

  void say(String text, {GhostPose pose = GhostPose.idle, int seconds = 8}) {
    message = text;
    this.pose = pose;
    _hide?.cancel();
    _hide = Timer(Duration(seconds: seconds), hide);
    notifyListeners();
  }

  void sayRandom() {
    final (text, personal) = MessageBank.random();
    say(text, pose: personal ? GhostPose.heart : GhostPose.idle);
  }

  void hide() {
    _hide?.cancel();
    message = null;
    pose = GhostPose.idle;
    notifyListeners();
  }

  /// Shows the how-to tip for a section the first time it's opened.
  /// Returns true if a tip was shown.
  Future<bool> tipOnce(String section) async {
    final tip = MessageBank.sectionTips[section];
    if (tip == null) return false;
    final key = 'tip_seen_$section';
    if (await Kv.get(key) != null) return false;
    await Kv.set(key, '1');
    say(tip, seconds: 12);
    return true;
  }
}

/// Ghost + speech bubble, listening to [Mascot].
/// [bubbleOnRight] puts the bubble beside the ghost instead of above it.
class MascotWithBubble extends StatelessWidget {
  const MascotWithBubble({
    super.key,
    this.height = 110,
    this.bubbleOnRight = true,
    this.overridePose,
  });

  final double height;
  final bool bubbleOnRight;
  final GhostPose? overridePose;

  @override
  Widget build(BuildContext context) {
    final m = Mascot.instance;
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final ghost = GestureDetector(
          onTap: m.message == null ? m.sayRandom : m.hide,
          child: Ghost(pose: overridePose ?? m.pose, height: height),
        );
        final bubble = AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween(begin: 0.9, end: 1.0).animate(anim),
              alignment: bubbleOnRight ? Alignment.bottomLeft : Alignment.bottomCenter,
              child: child,
            ),
          ),
          child: m.message == null
              ? const SizedBox.shrink(key: ValueKey('none'))
              : SpeechBubble(
                  key: ValueKey(m.message),
                  text: m.message!,
                  tailLeft: bubbleOnRight,
                  onTap: m.hide,
                ),
        );
        return bubbleOnRight
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ghost,
                  Padding(
                    padding: EdgeInsets.only(bottom: height * 0.45),
                    child: bubble,
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [bubble, const SizedBox(height: 4), ghost],
              );
      },
    );
  }
}

class SpeechBubble extends StatelessWidget {
  const SpeechBubble({
    super.key,
    required this.text,
    this.tailLeft = true,
    this.onTap,
  });

  final String text;
  final bool tailLeft;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: CustomPaint(
          painter: _BubblePainter(tailLeft: tailLeft),
          child: Padding(
            padding: EdgeInsets.fromLTRB(tailLeft ? 22 : 14, 12, 14, tailLeft ? 12 : 22),
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppPalette.ink,
                    height: 1.35,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({required this.tailLeft});
  final bool tailLeft;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 16.0, tail = 10.0;
    final rect = tailLeft
        ? Rect.fromLTWH(tail, 0, size.width - tail, size.height)
        : Rect.fromLTWH(0, 0, size.width, size.height - tail);
    final box = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(r)));
    final tip = Path();
    if (tailLeft) {
      final y = size.height - 22;
      tip
        ..moveTo(tail + 4, y - 8)
        ..lineTo(0, y + 6)
        ..lineTo(tail + 4, y + 2)
        ..close();
    } else {
      final x = size.width / 2;
      tip
        ..moveTo(x - 8, size.height - tail - 4)
        ..lineTo(x, size.height)
        ..lineTo(x + 8, size.height - tail - 4)
        ..close();
    }
    final path = Path.combine(PathOperation.union, box, tip);
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, Paint()..color = AppPalette.bubble);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = AppPalette.ghostLine,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.tailLeft != tailLeft;
}
