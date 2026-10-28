import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

enum AddAction { list, search, import, note }

/// The "+" menu: the screen blurs away and option cards spring up from the button.
Future<AddAction?> showAddMenu(BuildContext context) {
  return showGeneralDialog<AddAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 560),
    pageBuilder: (ctx, a, _) => _AddMenu(animation: a),
  );
}

class _AddMenu extends StatelessWidget {
  const _AddMenu({required this.animation});
  final Animation<double> animation;

  static const _options = [
    (AddAction.list, 'Create a List', 'Collect and organize your favorites', Icons.collections_bookmark_rounded,
        [Color(0xFFFF9A62), Color(0xFFE5484D)]),
    (AddAction.search, 'Find a Show or Book', 'Search series, anime and books, add in one tap', Icons.travel_explore_rounded,
        [Color(0xFF6E8BFF), Color(0xFF3A4FD8)]),
    (AddAction.import, 'Import', 'Turn screenshots or links into items', Icons.move_to_inbox_rounded,
        [Color(0xFFC86CFF), Color(0xFF7A3AE8)]),
    (AddAction.note, 'Write a Thought', 'A note, a review, anything on your mind', Icons.edit_note_rounded,
        [Color(0xFF4FD1A5), Color(0xFF1E9C78)]),
  ];

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    final calm = reduceMotion(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeOut.transform(animation.value);
        return Stack(children: [
          // Frosted backdrop: blur grows with the animation instead of popping in.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30 * t, sigmaY: 30 * t),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.45 * t)),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: bottom + 104,
            child: Glass(
              radius: 34,
              padding: const EdgeInsets.all(10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final (i, o) in _options.indexed) _staggered(i, calm, _option(context, rv, o)),
              ]),
            ),
          ),
          // ✕ sits exactly where the + was, turning from + into ✕.
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom + 24,
            child: Center(
              child: Semantics(
                button: true,
                label: 'Close',
                child: Pressable(
                  onTap: () => Navigator.pop(context),
                  scale: 0.9,
                  child: Transform.rotate(
                    angle: calm ? 0 : (1 - t) * -0.785, // 45° → 0 as it opens
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(color: rv.ink, shape: BoxShape.circle),
                      child: Icon(Icons.close_rounded, color: rv.onInk, size: 28),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }

  /// Each card rises from below with a little overshoot, one after another (bottom card first).
  Widget _staggered(int i, bool calm, Widget child) {
    final start = (3 - i) * 0.08;
    final curve = CurvedAnimation(
      parent: animation,
      curve: Interval(start, (start + 0.6).clamp(0, 1), curve: calm ? Curves.easeOut : Curves.easeOutBack),
      reverseCurve: const Interval(0, 0.6, curve: Curves.easeIn),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (_, c) => Opacity(
        opacity: curve.value.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, calm ? 0 : (1 - curve.value) * 60), child: c),
      ),
      child: child,
    );
  }

  Widget _option(BuildContext context, Rv rv, (AddAction, String, String, IconData, List<Color>) o) {
    final (action, title, subtitle, icon, colors) = o;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Semantics(
        button: true,
        label: title,
        child: Pressable(
          scale: 0.97,
          onTap: () => Navigator.pop(context, action),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: rv.surface, borderRadius: BorderRadius.circular(26)),
            child: Row(children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                  boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
                ),
                child: Icon(icon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: RvText.headline(rv.text)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: RvText.small(rv.text2)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
