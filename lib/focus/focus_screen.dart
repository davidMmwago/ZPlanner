import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../data/study_repo.dart';
import '../mascot/ghost.dart';
import '../mascot/mascot.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import 'focus_controller.dart';

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  final f = FocusController.instance;
  List<Module> _modules = [];
  int _todayMinutes = 0;
  int _lastSessions = -1;

  @override
  void initState() {
    super.initState();
    _load();
    f.addListener(_onTimer);
  }

  @override
  void dispose() {
    f.removeListener(_onTimer);
    super.dispose();
  }

  void _onTimer() {
    // Refresh today's total after a session is saved.
    if (f.sessionsThisRun != _lastSessions || f.phase == FocusPhase.idle) {
      _lastSessions = f.sessionsThisRun;
      _loadToday();
    }
  }

  Future<void> _load() async {
    final m = await AppDb.instance.modules();
    if (!mounted) return;
    setState(() {
      _modules = m;
      if (f.moduleId != null && !m.any((x) => x.id == f.moduleId)) f.moduleId = null;
    });
    _loadToday();
  }

  Future<void> _loadToday() async {
    final d = await StudyRepo.minutesPerDay(1);
    if (mounted) setState(() => _todayMinutes = d.first.minutes);
  }

  Color get _accent {
    final m = _modules.where((x) => x.id == f.moduleId);
    return m.isEmpty ? AppPalette.chart : Color(m.first.color);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Focus', style: Theme.of(context).textTheme.headlineMedium),
        toolbarHeight: 72,
      ),
      body: ListenableBuilder(
        listenable: f,
        builder: (context, _) => LayoutBuilder(builder: (context, cons) {
          final wide = cons.maxWidth > 760;
          final timer = _TimerPanel(controller: f, accent: _accent);
          final settings = _Settings(
            controller: f,
            modules: _modules,
            todayMinutes: _todayMinutes,
            onChanged: () => setState(() {}),
          );
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpace.l, 0, AppSpace.l, AppSpace.xl),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: timer),
                      const SizedBox(width: AppSpace.l),
                      Expanded(flex: 2, child: settings),
                    ],
                  )
                : Column(children: [timer, const SizedBox(height: AppSpace.l), settings]),
          );
        }),
      ),
    );
  }
}

class _TimerPanel extends StatelessWidget {
  const _TimerPanel({required this.controller, required this.accent});
  final FocusController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final f = controller;
    final left = f.remaining;
    final mm = two(left.inMinutes);
    final ss = two(left.inSeconds % 60);
    final label = switch (f.phase) {
      FocusPhase.idle => 'Ready when you are',
      FocusPhase.focus => f.state == TimerState.paused ? 'Paused' : 'Focusing',
      FocusPhase.rest => 'Break time',
    };
    final ringColor = f.phase == FocusPhase.rest ? AppPalette.moneyIn : accent;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.l),
        child: Column(
          children: [
            SizedBox(
              width: 300,
              height: 300,
              child: CustomPaint(
                painter: _RingPainter(progress: f.progress, color: ringColor),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$mm:$ss',
                        style: Theme.of(context).textTheme.displayMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [FontFeature.tabularFigures()],
                              color: AppPalette.ink,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(label, style: const TextStyle(color: AppPalette.muted)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.l),
            Wrap(
              spacing: AppSpace.s,
              runSpacing: AppSpace.s,
              alignment: WrapAlignment.center,
              children: _buttons(f),
            ),
            const SizedBox(height: AppSpace.l),
            // The ghost keeps her company here (with its speech bubble above).
            MascotWithBubble(height: 150, bubbleOnRight: false, overridePose: _poseFor(f)),
          ],
        ),
      ),
    );
  }

  GhostPose? _poseFor(FocusController f) =>
      f.phase == FocusPhase.rest ? f.pose : null; // otherwise follow what it's saying

  List<Widget> _buttons(FocusController f) {
    if (f.phase == FocusPhase.idle) {
      return [
        FilledButton.icon(
          onPressed: f.startFocus,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start focus'),
          style: FilledButton.styleFrom(minimumSize: const Size(180, 52)),
        ),
      ];
    }
    return [
      if (f.phase == FocusPhase.rest)
        FilledButton.tonalIcon(
          onPressed: f.skipBreak,
          icon: const Icon(Icons.skip_next),
          label: const Text('Skip break'),
        )
      else if (f.state == TimerState.running)
        FilledButton.tonalIcon(
          onPressed: f.pause,
          icon: const Icon(Icons.pause),
          label: const Text('Pause'),
        )
      else
        FilledButton.icon(
          onPressed: f.resume,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Resume'),
        ),
      OutlinedButton.icon(
        onPressed: f.stop,
        icon: const Icon(Icons.stop),
        label: Text(f.phase == FocusPhase.rest ? 'End break' : 'Stop'),
      ),
    ];
  }
}

class _Settings extends StatelessWidget {
  const _Settings({
    required this.controller,
    required this.modules,
    required this.todayMinutes,
    required this.onChanged,
  });
  final FocusController controller;
  final List<Module> modules;
  final int todayMinutes;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final f = controller;
    final locked = f.phase != FocusPhase.idle;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Studying', style: t.titleMedium),
                const SizedBox(height: AppSpace.s),
                DropdownButtonFormField<int?>(
                  initialValue: f.moduleId,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('No module')),
                    for (final m in modules)
                      DropdownMenuItem<int?>(
                        value: m.id,
                        child: Row(children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(color: Color(m.color), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Flexible(child: Text(m.name, overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                  ],
                  onChanged: locked
                      ? null
                      : (v) {
                          f.moduleId = v;
                          onChanged();
                        },
                ),
                const SizedBox(height: AppSpace.l),
                Text('Focus length', style: t.titleMedium),
                const SizedBox(height: AppSpace.s),
                _Choices(
                  values: const [15, 25, 45, 50],
                  selected: f.focusMinutes,
                  enabled: !locked,
                  onSelect: (v) {
                    f.focusMinutes = v;
                    onChanged();
                  },
                ),
                const SizedBox(height: AppSpace.m),
                Text('Break length', style: t.titleMedium),
                const SizedBox(height: AppSpace.s),
                _Choices(
                  values: const [5, 10, 15],
                  max: 60,
                  selected: f.breakMinutes,
                  enabled: !locked,
                  onSelect: (v) {
                    f.breakMinutes = v;
                    onChanged();
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.m),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.l),
            child: Row(
              children: [
                const Icon(Icons.today_outlined, color: AppPalette.muted),
                const SizedBox(width: AppSpace.m),
                Expanded(child: Text('Focused today', style: t.titleMedium)),
                Text(minutesText(todayMinutes),
                    style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Choices extends StatelessWidget {
  const _Choices({
    required this.values,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    this.max = 180,
  });
  final List<int> values;
  final int selected;
  final bool enabled;
  final ValueChanged<int> onSelect;
  final int max; // longest custom length allowed

  @override
  Widget build(BuildContext context) {
    final isCustom = !values.contains(selected);
    return Wrap(
      spacing: AppSpace.s,
      runSpacing: AppSpace.s,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text('$v min'),
            selected: v == selected,
            onSelected: enabled ? (_) => onSelect(v) : null,
          ),
        ChoiceChip(
          avatar: const Icon(Icons.tune, size: 18),
          label: Text(isCustom ? 'Custom: $selected min' : 'Custom'),
          selected: isCustom,
          onSelected: enabled
              ? (_) async {
                  final v = await _askMinutes(context, isCustom ? selected : values.last, max);
                  if (v != null) onSelect(v);
                }
              : null,
        ),
      ],
    );
  }
}

/// Small dialog to type a number of minutes (1 to [max]).
Future<int?> _askMinutes(BuildContext context, int initial, int max) {
  final ctrl = TextEditingController(text: '$initial');
  String? error;
  return showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) {
        void submit() {
          final v = int.tryParse(ctrl.text.trim());
          if (v == null || v < 1 || v > max) {
            setLocal(() => error = 'Enter a number from 1 to $max');
            return;
          }
          Navigator.pop(context, v);
        }

        return AlertDialog(
          title: const Text('Custom length'),
          content: SizedBox(
            width: 280,
            child: TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(suffixText: 'minutes', errorText: error),
              onSubmitted: (_) => submit(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: submit, child: const Text('Set')),
          ],
        );
      },
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: math.min(size.width, size.height) / 2 - stroke,
    );
    canvas.drawArc(
      rect, 0, math.pi * 2, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color.withValues(alpha: 0.15),
    );
    if (progress > 0) {
      canvas.drawArc(
        rect, -math.pi / 2, math.pi * 2 * progress, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}
