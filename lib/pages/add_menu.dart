import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

enum AddAction { list, search, import, note }

/// The "+" menu: the screen blurs away and option cards spring up from the button.
/// [from] is the + button's rect: the ✕ morphs out of it and the blur ripples from its centre.
Future<AddAction?> showAddMenu(BuildContext context, {required Rect from}) {
  return showGeneralDialog<AddAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 560),
    pageBuilder: (ctx, a, _) => Material(type: MaterialType.transparency, child: _AddMenu(animation: a, from: from)),
    // No route-level fade: an opacity layer over a BackdropFilter turns the blur off on device
    // (that's what made it pop in at the end). The menu animates itself.
    transitionBuilder: (ctx, a, _, child) => child,
  );
}

class _AddMenu extends StatelessWidget {
  const _AddMenu({required this.animation, required this.from});
  final Animation<double> animation;
  final Rect from;

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
        final t = Curves.easeOutCubic.transform(animation.value);
        return Stack(children: [
          // Frosted glass ripples out from the + button (and shrinks back into it on close).
          // A clipped constant blur renders reliably; fading or animating the blur radius pops on device.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: ClipOval(
                clipper: _Ripple(t, from.center),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: const ColoredBox(color: Color(0x73000000)),
                ),
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
          // The + pill itself morphs into the round ✕ (same centre), turning 45° as it goes.
          Positioned.fromRect(
            rect: Rect.fromCenter(
                center: from.center, width: from.width + (64 - from.width) * t, height: from.height + (64 - from.height) * t),
            child: Center(
              child: Semantics(
                button: true,
                label: 'Close',
                child: Pressable(
                  onTap: () => Navigator.pop(context),
                  scale: 0.9,
                  child: Container(
                    width: double.infinity, // fill the morphing rect
                    height: double.infinity,
                    decoration: BoxDecoration(color: rv.ink, borderRadius: BorderRadius.circular(100)),
                    // Only the glyph turns (45° → 0): rotating the still-oval pill makes it wobble.
                    child: Transform.rotate(
                      angle: calm ? 0 : (1 - t) * -0.785,
                      child: Icon(Icons.close_rounded, color: rv.onInk, size: 28 + 4 * (1 - t)), // + is 32
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

/// Circle centred on the + button whose radius grows from the button to the farthest screen corner.
class _Ripple extends CustomClipper<Rect> {
  _Ripple(this.t, this.c);
  final double t;
  final Offset c;

  @override
  Rect getClip(Size size) {
    final far = [Offset.zero, Offset(size.width, 0), Offset(0, size.height), Offset(size.width, size.height)]
        .map((p) => (p - c).distance)
        .reduce(math.max);
    return Rect.fromCircle(center: c, radius: 32 + (far - 32) * t);
  }

  @override
  bool shouldReclip(_Ripple old) => old.t != t || old.c != c;
}
