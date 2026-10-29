import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/study_repo.dart';
import '../mascot/ghost.dart';
import '../mascot/mascot.dart';
import '../mascot/messages.dart';
import '../notify/notifier.dart';

enum FocusPhase { idle, focus, rest }

enum TimerState { stopped, running, paused }

/// The Pomodoro timer. Lives for the whole app so it keeps going when she
/// switches sections. Based on an end time, so it stays correct even if the
/// app is minimised.
class FocusController extends ChangeNotifier {
  FocusController._();
  static final FocusController instance = FocusController._();

  int focusMinutes = 25;
  int breakMinutes = 5;
  int? moduleId;

  FocusPhase phase = FocusPhase.idle;
  TimerState state = TimerState.stopped;
  int sessionsThisRun = 0;

  DateTime? _endsAt;
  DateTime? _focusStartedAt;
  Duration _pausedLeft = Duration.zero;
  Timer? _ticker;
  final Set<int> _saidAt = {};

  Duration get total =>
      Duration(minutes: phase == FocusPhase.rest ? breakMinutes : focusMinutes);

  Duration get remaining {
    switch (state) {
      case TimerState.stopped:
        return total;
      case TimerState.paused:
        return _pausedLeft;
      case TimerState.running:
        final r = _endsAt!.difference(DateTime.now());
        return r.isNegative ? Duration.zero : r;
    }
  }

  double get progress {
    final t = total.inMilliseconds;
    if (t == 0) return 0;
    return (1 - remaining.inMilliseconds / t).clamp(0.0, 1.0).toDouble();
  }

  GhostPose get pose => switch (phase) {
        FocusPhase.rest => GhostPose.heart,
        _ => GhostPose.idle,
      };

  // ── Controls ───────────────────────────────────────────────
  void startFocus() {
    Notifier.askPermissionsOnce();
    phase = FocusPhase.focus;
    _focusStartedAt = DateTime.now();
    _saidAt.clear();
    _run(total);
    Mascot.instance.say(MessageBank.pick(MessageBank.focusStart));
  }

  void pause() {
    if (state != TimerState.running) return;
    _pausedLeft = remaining;
    state = TimerState.paused;
    _ticker?.cancel();
    Notifier.cancelFocus();
    notifyListeners();
  }

  void resume() {
    if (state != TimerState.paused) return;
    _run(_pausedLeft);
  }

  /// Stop early. Focus time of 5+ minutes still counts.
  Future<void> stop() async {
    if (phase == FocusPhase.focus) {
      final done = total - remaining;
      if (done.inMinutes >= 5) {
        await StudyRepo.logSession(
            moduleId: moduleId, started: _focusStartedAt ?? DateTime.now(), minutes: done.inMinutes);
      }
    }
    _reset();
  }

  void skipBreak() {
    _reset();
    startFocus();
  }

  void _run(Duration left) {
    _endsAt = DateTime.now().add(left);
    state = TimerState.running;
    // Rings even if the app is minimised or the screen is off.
    Notifier.focusEndsAt(_endsAt!, isBreak: phase == FocusPhase.rest);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    notifyListeners();
  }

  void _reset() {
    _ticker?.cancel();
    Notifier.cancelFocus();
    phase = FocusPhase.idle;
    state = TimerState.stopped;
    _endsAt = null;
    notifyListeners();
  }

  void _tick() {
    if (state != TimerState.running) return;
    if (remaining == Duration.zero) {
      _complete();
      return;
    }
    // Encouragement during focus: halfway for short sessions,
    // at a third and two-thirds for long ones.
    if (phase == FocusPhase.focus) {
      final marks = focusMinutes > 30 ? [33, 66] : [50];
      final pct = (progress * 100).floor();
      for (final m in marks) {
        if (pct >= m && _saidAt.add(m)) {
          final personal = m == marks.last;
          Mascot.instance.say(
            MessageBank.pick(personal ? MessageBank.fromYou : MessageBank.focusMid),
            pose: personal ? GhostPose.heart : GhostPose.idle,
          );
        }
      }
    }
    notifyListeners();
  }

  Future<void> _complete() async {
    _ticker?.cancel();
    HapticFeedback.heavyImpact();
    if (phase == FocusPhase.focus) {
      await StudyRepo.logSession(
          moduleId: moduleId, started: _focusStartedAt ?? DateTime.now(), minutes: focusMinutes);
      sessionsThisRun++;
      Mascot.instance.say(MessageBank.pick(MessageBank.focusDone), pose: GhostPose.flower, seconds: 12);
      phase = FocusPhase.rest;
      _run(total); // break starts automatically
    } else {
      Mascot.instance.say(MessageBank.pick(MessageBank.breakDone), seconds: 12);
      _reset();
    }
  }
}
