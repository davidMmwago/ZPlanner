import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/study_repo.dart';
import '../mascot/ghost.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsData {
  final ({int current, int best}) streak;
  final List<({DateTime day, int minutes})> days;
  final List<({String name, int color, int minutes})> modules;
  final int weekMinutes;
  final int weekSessions;
  final int weekCards;
  _StatsData(this.streak, this.days, this.modules, this.weekMinutes, this.weekSessions, this.weekCards);
}

class _StatsScreenState extends State<StatsScreen> {
  _StatsData? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final weekStart = dayOnly(DateTime.now()).subtract(const Duration(days: 6));
    final days = await StudyRepo.minutesPerDay(14);
    final d = _StatsData(
      await StudyRepo.streaks(),
      days,
      await StudyRepo.minutesPerModule(weekStart),
      days.skip(7).fold<int>(0, (s, e) => s + e.minutes),
      await StudyRepo.sessionsSince(weekStart),
      await StudyRepo.reviewsSince(weekStart),
    );
    if (mounted) setState(() => _data = d);
  }

  String _cheer(int streak) {
    if (streak == 0) return 'Start a streak today, even 15 minutes counts!';
    if (streak == 1) return 'Day one of your streak. Let\'s keep it going!';
    if (streak < 5) return '$streak days in a row. You\'re building something!';
    if (streak < 14) return '$streak day streak! I\'m so proud of you.';
    return '$streak days?! You\'re unstoppable, ${AppConfig.herName}.';
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const SectionAppBar(title: 'Stats'),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpace.l, 0, AppSpace.l, AppSpace.xl),
                children: [
                  // Streak hero
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.l),
                      child: Row(children: [
                        Ghost(
                          height: 120,
                          pose: d.streak.current >= 3 ? GhostPose.heart : GhostPose.flower,
                        ),
                        const SizedBox(width: AppSpace.l),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                              Text('${d.streak.current}',
                                  style: t.displayMedium?.copyWith(fontWeight: FontWeight.w700, color: AppPalette.ink)),
                              const SizedBox(width: AppSpace.s),
                              Text('day streak',
                                  style: t.titleMedium?.copyWith(color: AppPalette.muted)),
                            ]),
                            const SizedBox(height: 4),
                            Text(_cheer(d.streak.current), style: t.bodyLarge),
                            const SizedBox(height: 4),
                            Text('Best ever: ${d.streak.best} days',
                                style: const TextStyle(color: AppPalette.muted)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: AppSpace.m),
                  // This week tiles
                  Row(children: [
                    Expanded(child: _StatTile(label: 'Focused this week', value: minutesText(d.weekMinutes))),
                    const SizedBox(width: AppSpace.m),
                    Expanded(child: _StatTile(label: 'Sessions this week', value: '${d.weekSessions}')),
                    const SizedBox(width: AppSpace.m),
                    Expanded(child: _StatTile(label: 'Cards reviewed', value: '${d.weekCards}')),
                  ]),
                  const SizedBox(height: AppSpace.m),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.l),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Focus time, last 14 days', style: t.titleMedium),
                        const SizedBox(height: 2),
                        const Text('Tap a bar to see that day.',
                            style: TextStyle(color: AppPalette.muted, fontSize: 13)),
                        const SizedBox(height: AppSpace.l),
                        _DayBars(days: d.days),
                      ]),
                    ),
                  ),
                  const SizedBox(height: AppSpace.m),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.l),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('By module, last 7 days', style: t.titleMedium),
                        const SizedBox(height: AppSpace.m),
                        if (d.modules.isEmpty)
                          const Text('No focus sessions yet this week.',
                              style: TextStyle(color: AppPalette.muted))
                        else
                          _ModuleBars(rows: d.modules),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.m),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppPalette.muted, fontSize: 13)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600, color: AppPalette.ink)),
          ),
        ]),
      ),
    );
  }
}

/// Vertical bars, one per day. Single colour; the selected day is labelled.
class _DayBars extends StatefulWidget {
  const _DayBars({required this.days});
  final List<({DateTime day, int minutes})> days;

  @override
  State<_DayBars> createState() => _DayBarsState();
}

class _DayBarsState extends State<_DayBars> {
  late int _selected = widget.days.length - 1; // today

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final maxM = math.max(30, days.fold<int>(0, (m, e) => math.max(m, e.minutes)));
    final sel = days[_selected];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        '${friendlyDay(sel.day)}: ${minutesText(sel.minutes)}',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppPalette.ink),
      ),
      const SizedBox(height: AppSpace.m),
      SizedBox(
        height: 160,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque, // whole column is tappable
                onTap: () => setState(() => _selected = i),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Flexible(
                    child: FractionallySizedBox(
                      heightFactor: days[i].minutes == 0 ? 0.0 : math.max(0.03, days[i].minutes / maxM),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i == _selected ? AppPalette.chart : AppPalette.chart.withValues(alpha: 0.55),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                  Container(height: 1, color: const Color(0x22000000)), // baseline
                  const SizedBox(height: 6),
                  Text(
                    weekdaysShort[days[i].day.weekday - 1].substring(0, 1),
                    style: TextStyle(
                      fontSize: 12,
                      color: i == _selected ? AppPalette.ink : AppPalette.muted,
                      fontWeight: i == _selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }
}

/// Horizontal bars per module, labelled with name and time (not colour alone).
class _ModuleBars extends StatelessWidget {
  const _ModuleBars({required this.rows});
  final List<({String name, int color, int minutes})> rows;

  @override
  Widget build(BuildContext context) {
    final maxM = rows.first.minutes == 0 ? 1 : rows.first.minutes;
    return Column(children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: ModuleTag(name: r.name, color: r.color)),
              Text(minutesText(r.minutes), style: const TextStyle(color: AppPalette.ink)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: r.minutes / maxM,
                minHeight: 10,
                color: Color(r.color),
                backgroundColor: Color(r.color).withValues(alpha: 0.12),
              ),
            ),
          ]),
        ),
    ]);
  }
}
