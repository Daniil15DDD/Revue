import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'adaptive.dart';
import 'models.dart';
import 'store.dart';

bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Feedback on touch-down, not on release: shrinks slightly the instant a finger lands.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _set(false);
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down && !reduceMotion(context) ? 0.97 : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _down ? 0.85 : 1,
          duration: const Duration(milliseconds: 90),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Thin rounded track with a coloured fill that never shrinks below a dot (like the Stats bars).
class ProgressTrack extends StatelessWidget {
  const ProgressTrack({super.key, required this.value, required this.color, this.height = 8, this.track});
  final double value; // 0..1
  final Color color;
  final double height;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    final bg = track ?? CupertinoDynamicColor.resolve(CupertinoColors.tertiarySystemFill, context);
    return LayoutBuilder(builder: (context, c) {
      final target = (c.maxWidth * value.clamp(0, 1)).clamp(height, c.maxWidth);
      return Container(
        height: height,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(height)),
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: target),
          duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 550),
          curve: Curves.easeOutCubic,
          builder: (_, w, _) => Container(
            width: w,
            height: height,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height)),
          ),
        ),
      );
    });
  }
}

/// Raised surface for cards: white on grey in light mode, lifted grey on black in dark mode.
BoxDecoration surface(BuildContext context, {double radius = 22}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: Theme.of(context).cardTheme.color,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: dark
        ? null
        : const [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4))],
  );
}

TextStyle _tight(double size, FontWeight w, Color c) =>
    TextStyle(fontSize: size, fontWeight: w, color: c, letterSpacing: size >= 24 ? -0.022 * size : 0, height: 1.1);

/// The home-page Stats card: total for the period, one bar per list (busiest first, top 4 until expanded).
class StatsCard extends StatefulWidget {
  const StatsCard({
    super.key,
    required this.store,
    required this.period,
    required this.selectedListId,
    required this.onSelectList,
    required this.onPeriod,
    required this.onNewList,
    required this.onEditList,
  });

  final Store store;
  final Period period;
  final String? selectedListId;
  final ValueChanged<String?> onSelectList;
  final VoidCallback onPeriod;
  final VoidCallback onNewList;
  final ValueChanged<RevueList> onEditList;

  @override
  State<StatsCard> createState() => _StatsCardState();
}

class _StatsCardState extends State<StatsCard> {
  static const _collapsed = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final StatsCard(:store, :period, :selectedListId, :onSelectList, :onPeriod, :onNewList, :onEditList) = widget;
    final ios = isIOS(context);
    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondary = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final accent = Theme.of(context).colorScheme.primary;
    final counts = {for (final l in store.lists) l.id: store.count(period, listId: l.id)};
    final most = counts.values.fold(0, (a, b) => a > b ? a : b);
    final ranked = [...store.lists]..sort((a, b) => counts[b.id]!.compareTo(counts[a.id]!)); // stable: ties keep order
    final shown = _expanded || ranked.length <= _collapsed + 1
        ? ranked
        : [...ranked.take(_collapsed), ...ranked.skip(_collapsed).where((l) => l.id == selectedListId)];
    const tabular = [FontFeature.tabularFigures()];

    return Container(
      decoration: surface(context),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text('Stats', style: _tight(28, FontWeight.w700, label)),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: 'Period: ${period.label}',
            child: Pressable(
              onTap: onPeriod,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CupertinoDynamicColor.resolve(CupertinoColors.tertiarySystemFill, context),
                ),
                child: Icon(ios ? CupertinoIcons.calendar : Icons.calendar_today_outlined, size: 17, color: label),
              ),
            ),
          ),
          const Spacer(),
          Text('${store.count(period)}', style: _tight(34, FontWeight.w700, label).copyWith(fontFeatures: tabular)),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: Text(period.label, style: TextStyle(fontSize: 13, color: secondary)),
        ),
        for (final l in shown)
          Semantics(
            button: true,
            selected: selectedListId == l.id,
            label: '${l.name}, ${counts[l.id]} items',
            child: Pressable(
              onTap: () => onSelectList(selectedListId == l.id ? null : l.id),
              onLongPress: () => onEditList(l),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: selectedListId == null || selectedListId == l.id ? 1 : 0.4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(
                        child: Text(l.display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: label)),
                      ),
                      Text('${counts[l.id]}',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: secondary, fontFeatures: tabular)),
                    ]),
                    const SizedBox(height: 10),
                    ProgressTrack(value: most == 0 ? 0 : counts[l.id]! / most, color: Color(l.color)),
                  ]),
                ),
              ),
            ),
          ),
        if (ranked.length > shown.length || _expanded && ranked.length > _collapsed + 1)
          Pressable(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Text(_expanded ? 'Show Less' : 'Show All (${ranked.length})',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: secondary)),
            ),
          ),
        Pressable(
          onTap: onNewList,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              Icon(ios ? CupertinoIcons.plus_circle_fill : Icons.add_circle, size: 20, color: accent),
              const SizedBox(width: 8),
              Text('New List', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: accent)),
            ]),
          ),
        ),
      ]),
    );
  }
}
