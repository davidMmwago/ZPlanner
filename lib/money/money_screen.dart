import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/money_repo.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Simple planner: money coming in and going out, month by month.
class MoneyScreen extends StatefulWidget {
  const MoneyScreen({super.key});

  @override
  State<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends State<MoneyScreen> {
  List<MoneyEntry>? _all;
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final a = await MoneyRepo.all();
    if (mounted) setState(() => _all = a);
  }

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  Future<void> _edit([MoneyEntry? e]) async {
    final r = await showMoneyDialog(context, e, _month);
    if (r == null) return;
    if (r.delete && e != null) {
      await MoneyRepo.delete(e.id);
    } else if (e == null) {
      await MoneyRepo.add(r.title, r.amount, r.isIncome, r.date, r.monthly);
    } else {
      await MoneyRepo.update(e.id, r.title, r.amount, r.isIncome, r.date, r.monthly);
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    return Scaffold(
      appBar: const SectionAppBar(title: 'Money'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: all == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, cons) {
              final wide = cons.maxWidth > 820;
              final month = _MonthPanel(
                month: _month,
                entries: all.where((e) => e.occursIn(_month.year, _month.month)).toList(),
                onPrev: () => _shift(-1),
                onNext: () => _shift(1),
                onTap: _edit,
              );
              final ahead = _AheadPanel(all: all, from: _month);
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpace.l, 0, AppSpace.l, 100),
                child: wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 4, child: month),
                        const SizedBox(width: AppSpace.l),
                        Expanded(flex: 3, child: ahead),
                      ])
                    : Column(children: [month, const SizedBox(height: AppSpace.l), ahead]),
              );
            }),
    );
  }
}

class _MonthPanel extends StatelessWidget {
  const _MonthPanel({
    required this.month,
    required this.entries,
    required this.onPrev,
    required this.onNext,
    required this.onTap,
  });
  final DateTime month;
  final List<MoneyEntry> entries;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<MoneyEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final income = entries.where((e) => e.isIncome).fold<double>(0, (s, e) => s + e.amount);
    final spend = entries.where((e) => !e.isIncome).fold<double>(0, (s, e) => s + e.amount);
    final net = income - spend;
    final sorted = [...entries]..sort((a, b) {
        if (a.isIncome != b.isIncome) return a.isIncome ? -1 : 1;
        return a.date.day.compareTo(b.date.day);
      });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text('${monthsLong[month.month - 1]} ${month.year}',
                  textAlign: TextAlign.center, style: t.titleLarge),
            ),
            IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
          ]),
          const SizedBox(height: AppSpace.m),
          Row(children: [
            Expanded(child: _Tile(label: 'Coming in', value: money(income), color: AppPalette.moneyIn)),
            const SizedBox(width: AppSpace.s),
            Expanded(child: _Tile(label: 'Going out', value: money(spend), color: AppPalette.moneyOut)),
            const SizedBox(width: AppSpace.s),
            Expanded(
              child: _Tile(
                label: 'Left over',
                value: money(net, sign: true),
                color: net >= 0 ? AppPalette.moneyIn : AppPalette.moneyOut,
                strong: true,
              ),
            ),
          ]),
          const SizedBox(height: AppSpace.l),
          if (sorted.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpace.l),
              child: Text('Nothing planned for this month yet.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppPalette.muted)),
            )
          else
            for (final e in sorted)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => onTap(e),
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: (e.isIncome ? AppPalette.moneyIn : AppPalette.moneyOut)
                      .withValues(alpha: 0.12),
                  child: Icon(
                    e.isIncome ? Icons.south_west : Icons.north_east,
                    size: 18,
                    color: e.isIncome ? AppPalette.moneyIn : AppPalette.moneyOut,
                  ),
                ),
                title: Text(e.title),
                subtitle: Text(
                  e.monthly ? 'Every month · day ${e.date.day}' : friendlyDay(e.date),
                  style: const TextStyle(color: AppPalette.muted),
                ),
                trailing: Text(
                  money(e.signed, sign: true),
                  maxLines: 1,
                  softWrap: false,
                  style: t.titleMedium?.copyWith(
                    color: e.isIncome ? AppPalette.moneyIn : AppPalette.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
        ]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.color, this.strong = false});
  final String label;
  final String value;
  final Color color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.m),
      decoration: BoxDecoration(
        color: color.withValues(alpha: strong ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(AppShape.radiusSmall),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppPalette.muted, fontSize: 13)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppPalette.ink,
                  )),
        ),
      ]),
    );
  }
}

/// The next 6 months at a glance, with a running total.
class _AheadPanel extends StatelessWidget {
  const _AheadPanel({required this.all, required this.from});
  final List<MoneyEntry> all;
  final DateTime from;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    var running = 0.0;
    final rows = <Widget>[];
    for (var i = 0; i < 6; i++) {
      final m = DateTime(from.year, from.month + i);
      final net = all
          .where((e) => e.occursIn(m.year, m.month))
          .fold<double>(0, (s, e) => s + e.signed);
      running += net;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(
            width: 135,
            child: Text(
              m.year == DateTime.now().year
                  ? monthsShort[m.month - 1]
                  : '${monthsShort[m.month - 1]} ${m.year}',
              maxLines: 1,
              softWrap: false,
              style: t.titleSmall,
            ),
          ),
          Expanded(child: _OneLine(money(net, sign: true),
              style: TextStyle(color: net >= 0 ? AppPalette.moneyIn : AppPalette.moneyOut))),
          const SizedBox(width: AppSpace.s),
          Expanded(child: _OneLine(money(running), alignRight: true,
              style: t.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]))),
        ]),
      ));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Next 6 months', style: t.titleMedium),
          const SizedBox(height: 2),
          const Text('Left over each month, and the running total.',
              style: TextStyle(color: AppPalette.muted, fontSize: 13)),
          const Divider(height: AppSpace.l),
          const Row(children: [
            SizedBox(width: 135, child: Text('Month', style: TextStyle(color: AppPalette.muted, fontSize: 12))),
            Expanded(child: Text('Left over', style: TextStyle(color: AppPalette.muted, fontSize: 12))),
            SizedBox(width: AppSpace.s),
            Expanded(
                child: Text('Running total',
                    textAlign: TextAlign.right, style: TextStyle(color: AppPalette.muted, fontSize: 12))),
          ]),
          ...rows,
        ]),
      ),
    );
  }
}

class MoneyInput {
  final String title;
  final double amount;
  final bool isIncome;
  final DateTime date;
  final bool monthly;
  final bool delete;
  MoneyInput(this.title, this.amount, this.isIncome, this.date, this.monthly, {this.delete = false});
}

Future<MoneyInput?> showMoneyDialog(BuildContext context, MoneyEntry? e, DateTime month) {
  final title = TextEditingController(text: e?.title);
  final amount = TextEditingController(text: e == null ? '' : e.amount.toStringAsFixed(2));
  var isIncome = e?.isIncome ?? false;
  var monthly = e?.monthly ?? false;
  final now = DateTime.now();
  var date = e?.date ??
      ((month.year == now.year && month.month == now.month) ? dayOnly(now) : month);

  return showDialog<MoneyInput>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text(e == null ? 'Add money plan' : 'Edit'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Going out'), icon: Icon(Icons.north_east)),
                ButtonSegment(value: true, label: Text('Coming in'), icon: Icon(Icons.south_west)),
              ],
              selected: {isIncome},
              onSelectionChanged: (s) => setLocal(() => isIncome = s.first),
            ),
            const SizedBox(height: AppSpace.m),
            TextField(
              controller: title,
              autofocus: e == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'What for?',
                hintText: isIncome ? '' : '',
              ),
            ),
            const SizedBox(height: AppSpace.m),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '${AppConfig.currency} '),
            ),
            const SizedBox(height: AppSpace.m),
            Row(children: [
              InputChip(
                avatar: const Icon(Icons.event_outlined, size: 18),
                label: Text(monthly ? 'From ${friendlyDay(date)}' : friendlyDay(date)),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(now.year - 2),
                    lastDate: DateTime(now.year + 5),
                  );
                  if (picked != null) setLocal(() => date = picked);
                },
              ),
              const Spacer(),
              const Text('Every month'),
              Switch(value: monthly, onChanged: (v) => setLocal(() => monthly = v)),
            ]),
          ]),
        ),
        actions: [
          if (e != null)
            TextButton(
              onPressed: () => Navigator.pop(context, MoneyInput('', 0, false, date, false, delete: true)),
              child: const Text('Delete', style: TextStyle(color: AppPalette.moneyOut)),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final t = title.text.trim();
              final a = double.tryParse(amount.text.replaceAll(',', '.').trim());
              if (t.isEmpty || a == null || a <= 0) return;
              Navigator.pop(context, MoneyInput(t, a, isIncome, date, monthly));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// Text that never wraps; shrinks to fit instead.
class _OneLine extends StatelessWidget {
  const _OneLine(this.text, {this.style, this.alignRight = false});
  final String text;
  final TextStyle? style;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(text, maxLines: 1, softWrap: false, style: style),
    );
  }
}
