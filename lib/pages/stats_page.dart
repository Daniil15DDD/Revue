import 'package:flutter/material.dart';

import '../adaptive.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

/// Stats for everything: total in the period, a bar per list, and what's in progress / finished.
class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.store});
  final Store store;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  Period _period = Period.all;

  Store get store => widget.store;

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    const tabular = [FontFeature.tabularFigures()];
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final from = _period.start(DateTime.now());
        final inPeriod = store.items.where((i) => from == null || !i.created.isBefore(from)).toList();
        final finished = store.items.where((i) => i.finishedAt != null && (from == null || !i.finishedAt!.isBefore(from))).length;
        final active = store.items.where((i) => i.status == Status.active).length;
        final episodes = store.items.where((i) => i.kind == Kind.show).fold(0, (a, i) => a + i.progress);
        final pages = store.items.where((i) => i.kind == Kind.book).fold(0, (a, i) => a + i.progress);
        final counts = {for (final l in store.lists) l.id: store.count(_period, listId: l.id)};
        final most = counts.values.fold(0, (a, b) => a > b ? a : b);
        final ranked = [...store.lists]..sort((a, b) => counts[b.id]!.compareTo(counts[a.id]!));
        return Scaffold(
          body: ListView(padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 14, 16, 130), children: [
            Row(children: [
              Text('Stats', style: RvText.display(rv.text)),
              const Spacer(),
              PillButton(label: _period.label, icon: Icons.calendar_today_rounded, primary: false, compact: true, onTap: _pickPeriod),
            ]),
            const SizedBox(height: 18),
            // Hero number.
            Container(
              padding: const EdgeInsets.all(22),
              decoration: surface(context, radius: 30),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('SAVED', style: RvText.label(rv.text2)),
                const SizedBox(height: 4),
                Text('${inPeriod.length}',
                    style: TextStyle(
                        fontFamily: font, fontSize: 64, fontWeight: FontWeight.w800, letterSpacing: -2.5, color: rv.text, fontFeatures: tabular)),
                Text(_period == Period.all ? 'things in your library' : 'added ${_period.label.toLowerCase()}',
                    style: RvText.body(rv.text2)),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _tile(context, '$active', 'In progress', Icons.play_arrow_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _tile(context, '$finished', 'Finished', Icons.check_rounded)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _tile(context, '$episodes', 'Episodes watched', Icons.live_tv_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _tile(context, '$pages', 'Pages read', Icons.menu_book_rounded)),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
              decoration: surface(context, radius: 30),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('BY LIST', style: RvText.label(rv.text2)),
                const SizedBox(height: 8),
                if (ranked.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('Create a list to see it here.', style: RvText.body(rv.text2)),
                  ),
                for (final l in ranked)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(
                          child: Text(l.display,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RvText.body(rv.text).copyWith(fontWeight: FontWeight.w600)),
                        ),
                        Text('${counts[l.id]}', style: RvText.body(rv.text2).copyWith(fontWeight: FontWeight.w700, fontFeatures: tabular)),
                      ]),
                      const SizedBox(height: 10),
                      ProgressTrack(value: most == 0 ? 0 : counts[l.id]! / most, color: Color(l.color)),
                    ]),
                  ),
              ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _tile(BuildContext context, String value, String label, IconData icon) {
    final rv = Rv.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: surface(context, radius: 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: rv.accent, size: 22),
        const SizedBox(height: 14),
        Text(value,
            style: TextStyle(
                fontFamily: font,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                color: rv.text,
                fontFeatures: const [FontFeature.tabularFigures()])),
        Text(label, style: RvText.small(rv.text2)),
      ]),
    );
  }

  Future<void> _pickPeriod() async {
    final p = await pickOption<Period>(context, [for (final p in Period.values) SheetOption(p, p.label)], title: 'Show stats for');
    if (p != null) setState(() => _period = p);
  }
}
