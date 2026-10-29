import 'dart:async';

import 'package:flutter/material.dart';

import '../cards/decks_screen.dart';
import '../focus/focus_screen.dart';
import '../mascot/mascot.dart';
import '../mascot/messages.dart';
import '../money/money_screen.dart';
import '../planner/planner_screen.dart';
import '../settings/settings_screen.dart';
import '../stats/stats_screen.dart';
import 'modules_screen.dart';

/// Main layout: side navigation rail + the selected section,
/// with the ghost sitting at the bottom-left.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _sections = <_Section>[
    _Section('Modules', Icons.folder_outlined, Icons.folder),
    _Section('Focus', Icons.timer_outlined, Icons.timer),
    _Section('Cue cards', Icons.style_outlined, Icons.style),
    _Section('Planner', Icons.checklist_outlined, Icons.checklist),
    _Section('Money', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet),
    _Section('Stats', Icons.insights_outlined, Icons.insights),
    _Section('Settings', Icons.settings_outlined, Icons.settings),
  ];

  @override
  void initState() {
    super.initState();
    // Say hi shortly after opening (or explain Modules the very first time).
    Timer(const Duration(milliseconds: 1200), () async {
      if (!mounted) return;
      final tipShown = await Mascot.instance.tipOnce('Modules');
      if (!tipShown && mounted) Mascot.instance.say(MessageBank.pick(MessageBank.greeting));
    });
  }

  void _select(int i) {
    setState(() => _index = i);
    Mascot.instance.tipOnce(_sections[i].label);
  }

  Widget _body() {
    switch (_index) {
      case 0:
        return const ModulesScreen();
      case 1:
        return const FocusScreen();
      case 2:
        return const DecksScreen();
      case 3:
        return const PlannerScreen();
      case 4:
        return const MoneyScreen();
      case 5:
        return const StatsScreen();
      default:
        return const SettingsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  groupAlignment: -0.85,
                  destinations: [
                    for (final s in _sections)
                      NavigationRailDestination(
                        icon: Icon(s.icon),
                        selectedIcon: Icon(s.selectedIcon),
                        label: Text(s.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1, thickness: 1, color: Color(0x11000000)),
                Expanded(
                  child: KeyedSubtree(key: ValueKey(_index), child: _body()),
                ),
              ],
            ),
            // The ghost lives at the bottom of the side bar; its speech bubble
            // floats out over the page. (The Focus page has its own big ghost.)
            if (_index != 1)
              const Positioned(
                left: 10,
                bottom: 8,
                child: MascotWithBubble(height: 104),
              ),
          ],
        ),
      ),
    );
  }
}

class _Section {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  const _Section(this.label, this.icon, this.selectedIcon);
}
