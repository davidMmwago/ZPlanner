import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../data/todo_repo.dart';
import '../google/google_api.dart';
import '../google/google_auth.dart';
import '../mascot/ghost.dart';
import '../mascot/mascot.dart';
import '../mascot/messages.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'todo_service.dart';

/// To-dos (with reminders) plus her Google Calendar events for the next
/// two weeks, when Google is connected.
class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  List<Todo>? _todos;
  List<Module> _modules = [];
  List<CalEvent> _events = [];
  String? _calError;
  bool _showDone = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final t = await TodoRepo.all();
    final m = await AppDb.instance.modules();
    if (mounted) {
      setState(() {
        _todos = t;
        _modules = m;
      });
    }
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    if (!GoogleAuth.instance.signedIn) {
      if (_events.isNotEmpty && mounted) setState(() => _events = []);
      return;
    }
    try {
      final from = dayOnly(DateTime.now());
      final ev = await GoogleApi.events(from, from.add(const Duration(days: 14)));
      // Hide events that are this app's own to-dos (they're already listed).
      final linked = {for (final t in _todos ?? const <Todo>[]) if (t.gcalId != null) t.gcalId};
      if (mounted) {
        setState(() {
          _events = ev.where((e) => !linked.contains(e.id)).toList();
          _calError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _calError = '$e');
    }
  }

  void _report(String? problem) {
    if (problem != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  Future<void> _edit([Todo? todo]) async {
    final r = await showTodoDialog(context, _modules, todo);
    if (r == null) return;
    if (todo == null) {
      _report(await TodoService.add(r.title, r.due, r.hasTime, r.moduleId, toCalendar: r.toCalendar));
    } else {
      _report(await TodoService.update(todo, r.title, r.due, r.hasTime, r.moduleId,
          toCalendar: r.toCalendar));
    }
    _refresh();
  }

  Future<void> _toggle(Todo t) async {
    await TodoService.setDone(t, !t.done);
    if (!t.done) {
      Mascot.instance.say(MessageBank.pick(MessageBank.todoDone), pose: GhostPose.flower, seconds: 4);
    }
    _refresh();
  }

  Future<void> _delete(Todo t) async {
    await TodoService.delete(t);
    _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Deleted "${t.title}"'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await TodoService.add(t.title, t.due, t.hasTime, t.moduleId, toCalendar: t.gcalId != null);
          _refresh();
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final todos = _todos;
    return Scaffold(
      appBar: SectionAppBar(title: 'Planner', actions: [
        TextButton.icon(
          onPressed: () => setState(() => _showDone = !_showDone),
          icon: Icon(_showDone ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          label: Text(_showDone ? 'Hide done' : 'Show done'),
        ),
        const SizedBox(width: AppSpace.m),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add to-do'),
      ),
      body: todos == null
          ? const Center(child: CircularProgressIndicator())
          : todos.where((t) => !t.done).isEmpty && !_showDone && _events.isEmpty
              ? const EmptyState(title: 'All clear!', subtitle: 'Nothing on your list. Add a to-do with the button below.')
              : RefreshIndicator(onRefresh: _refresh, child: _list(todos)),
    );
  }

  Widget _list(List<Todo> todos) {
    final today = dayOnly(DateTime.now());
    final groups = <String, List<Object>>{
      'Overdue': [],
      'Today': [],
      'Tomorrow': [],
      'Coming up': [],
      'Someday': [],
      'Done': [],
    };
    String dayGroup(DateTime d) {
      final diff = dayOnly(d).difference(today).inDays;
      return diff <= 0 ? 'Today' : diff == 1 ? 'Tomorrow' : 'Coming up';
    }

    for (final t in todos) {
      if (t.done) {
        if (_showDone) groups['Done']!.add(t);
        continue;
      }
      final due = t.due;
      if (due == null) {
        groups['Someday']!.add(t);
        continue;
      }
      final diff = dayOnly(due).difference(today).inDays;
      final overdue = t.hasTime ? due.isBefore(DateTime.now()) : diff < 0;
      groups[overdue ? 'Overdue' : dayGroup(due)]!.add(t);
    }
    for (final e in _events) {
      if (e.end != null && e.end!.isBefore(DateTime.now()) && !e.allDay) continue; // already over
      groups[dayGroup(e.start)]!.add(e);
    }
    DateTime? when(Object o) => o is Todo ? o.due : (o as CalEvent).start;
    for (final g in ['Today', 'Tomorrow', 'Coming up']) {
      groups[g]!.sort((a, b) => (when(a) ?? today).compareTo(when(b) ?? today));
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpace.l, 0, AppSpace.l, 100),
      children: [
        if (_calError != null)
          Card(
            color: AppPalette.moneyOut.withValues(alpha: 0.08),
            child: ListTile(
              leading: const Icon(Icons.event_busy_outlined),
              title: const Text('Couldn\'t load Google Calendar'),
              subtitle: Text(_calError!, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: TextButton(onPressed: _loadEvents, child: const Text('Retry')),
            ),
          ),
        for (final e in groups.entries)
          if (e.value.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, AppSpace.m, 0, AppSpace.s),
              child: Text(
                e.key,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: e.key == 'Overdue' ? AppPalette.moneyOut : AppPalette.muted,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            for (final o in e.value)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.s),
                child: o is CalEvent
                    ? _EventTile(event: o)
                    : Dismissible(
                        key: ValueKey((o as Todo).id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: AppSpace.l),
                          decoration: BoxDecoration(
                            color: AppPalette.moneyOut.withValues(alpha: 0.15),
                            borderRadius: AppShape.card,
                          ),
                          child: const Icon(Icons.delete_outline, color: AppPalette.moneyOut),
                        ),
                        onDismissed: (_) => _delete(o),
                        child: _TodoTile(todo: o, onToggle: () => _toggle(o), onTap: () => _edit(o)),
                      ),
              ),
          ],
      ],
    );
  }
}

/// A Google Calendar event (read-only here).
class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});
  final CalEvent event;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final end = e.end;
    final time = e.allDay
        ? 'All day'
        : '${hhmm(e.start)}${end != null ? ' – ${hhmm(end)}' : ''}';
    return Card(
      color: AppPalette.chart.withValues(alpha: 0.07),
      child: ListTile(
        leading: const Padding(
          padding: EdgeInsets.only(left: 12, right: 4),
          child: Icon(Icons.event_outlined, color: AppPalette.chart),
        ),
        title: Text(e.title),
        subtitle: Text('${friendlyDay(e.start)} · $time',
            style: const TextStyle(color: AppPalette.muted, fontSize: 13)),
      ),
    );
  }
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({required this.todo, required this.onToggle, required this.onTap});
  final Todo todo;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = todo;
    final due = t.due;
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Checkbox(value: t.done, onChanged: (_) => onToggle()),
        title: Text(
          t.title,
          style: t.done
              ? const TextStyle(decoration: TextDecoration.lineThrough, color: AppPalette.muted)
              : null,
        ),
        subtitle: (due == null && t.moduleName == null)
            ? null
            : Wrap(spacing: AppSpace.m, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (due != null)
                  Text(
                    '${friendlyDay(due)}${t.hasTime ? ' · ${hhmm(due)}' : ''}',
                    style: const TextStyle(color: AppPalette.muted, fontSize: 13),
                  ),
                if (t.moduleName != null)
                  ModuleTag(name: t.moduleName!, color: t.moduleColor ?? 0xFF8A8797),
                if (t.gcalId != null)
                  const Icon(Icons.event_available, size: 16, color: AppPalette.muted),
              ]),
      ),
    );
  }
}

class TodoInput {
  final String title;
  final DateTime? due;
  final bool hasTime;
  final int? moduleId;
  final bool toCalendar;
  TodoInput(this.title, this.due, this.hasTime, this.moduleId, this.toCalendar);
}

Future<TodoInput?> showTodoDialog(BuildContext context, List<Module> modules, Todo? todo) {
  final title = TextEditingController(text: todo?.title);
  DateTime? date = todo?.due == null ? null : dayOnly(todo!.due!);
  TimeOfDay? time = (todo?.hasTime ?? false) ? TimeOfDay.fromDateTime(todo!.due!) : null;
  int? moduleId = todo?.moduleId;
  final google = GoogleAuth.instance.signedIn;
  var toCalendar = todo == null ? google : todo.gcalId != null;

  return showDialog<TodoInput>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text(todo == null ? 'New to-do' : 'Edit to-do'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'What needs doing?'),
            ),
            const SizedBox(height: AppSpace.m),
            Wrap(spacing: AppSpace.s, runSpacing: AppSpace.s, children: [
              InputChip(
                avatar: const Icon(Icons.event_outlined, size: 18),
                label: Text(date == null ? 'Add date' : friendlyDay(date!)),
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date ?? now,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 3),
                  );
                  if (picked != null) setLocal(() => date = picked);
                },
                onDeleted: date == null ? null : () => setLocal(() {
                      date = null;
                      time = null;
                    }),
              ),
              if (date != null)
                InputChip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text(time == null ? 'Add time' : time!.format(context)),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: time ?? const TimeOfDay(hour: 9, minute: 0),
                    );
                    if (picked != null) setLocal(() => time = picked);
                  },
                  onDeleted: time == null ? null : () => setLocal(() => time = null),
                ),
            ]),
            const SizedBox(height: AppSpace.m),
            ModulePicker(modules: modules, value: moduleId, onChanged: (v) => moduleId = v),
            if (google && date != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Add to Google Calendar'),
                value: toCalendar,
                onChanged: (v) => setLocal(() => toCalendar = v),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final t = title.text.trim();
              if (t.isEmpty) return;
              DateTime? due;
              if (date != null) {
                due = DateTime(date!.year, date!.month, date!.day, time?.hour ?? 0, time?.minute ?? 0);
              }
              Navigator.pop(context, TodoInput(t, due, time != null, moduleId, toCalendar));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
