import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'store.dart';
import 'theme.dart';

bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Critically damped spring (no bounce) for UI, slight bounce for things the finger "throws".
SpringDescription spring({double response = 0.38, double damping = 1.0}) =>
    SpringDescription.withDampingRatio(mass: 1, stiffness: (2 * 3.14159 / response) * (2 * 3.14159 / response), ratio: damping);

/// Feedback on touch-down, not on release: shrinks slightly the instant a finger lands.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.96});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _focused = false; // keyboard / switch-access focus, shown as a ring

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    // Enter / Space activate it like a tap (keyboards, D-pads, Switch Access).
    return FocusableActionDetector(
      enabled: widget.onTap != null,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap?.call();
          return null;
        }),
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: _focused ? Border.all(color: Rv.of(context).accent, width: 2.5) : null,
        ),
        child: _gestures(enabled),
      ),
    );
  }

  Widget _gestures(bool enabled) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick(); // a light tick on every committed tap
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _set(false);
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down && !reduceMotion(context) ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 260),
        curve: _down ? Curves.easeOut : Curves.easeOutBack, // a hint of spring on release
        child: AnimatedOpacity(opacity: _down ? 0.82 : 1, duration: const Duration(milliseconds: 90), child: widget.child),
      ),
    );
  }
}

/// Frosted layer for floating chrome (tab bar, sheets). Falls back to solid when blur is unwanted.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = 32, this.padding = EdgeInsets.zero});
  final Widget child;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: rv.glass,
            borderRadius: shape,
            border: Border.all(color: rv.stroke),
            // bright top edge: light catching the material
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white.withValues(alpha: rv.dark ? 0.06 : 0.35), Colors.transparent],
              stops: const [0, 0.4],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Pill button. Primary = solid ink (white on dark, black on light); secondary = raised fill.
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label, this.icon, this.onTap, this.primary = true, this.compact = false, this.color});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool compact;
  final Color? color; // accent fill instead of ink

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    final bg = color ?? (primary ? rv.ink : rv.raised);
    final fg = color != null ? Colors.white : (primary ? rv.onInk : rv.text);
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: Pressable(
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            height: compact ? 40 : 52,
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 22),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) ...[Icon(icon, size: compact ? 18 : 20, color: fg), const SizedBox(width: 8)],
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: font, fontSize: compact ? 15 : 16, fontWeight: FontWeight.w700, color: fg)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Round icon button (back, more, close…).
class RoundButton extends StatelessWidget {
  const RoundButton({super.key, required this.icon, required this.onTap, this.tooltip, this.size = 44, this.filled = true});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    return Semantics(
      button: true,
      label: tooltip,
      child: Pressable(
        onTap: onTap,
        scale: 0.9,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: filled ? rv.raised : Colors.transparent),
          child: Icon(icon, size: size * 0.46, color: rv.text),
        ),
      ),
    );
  }
}

/// Selectable capsule for chip rows: selected = solid ink with soft corners (like the "All" tab).
class Tag extends StatelessWidget {
  const Tag({super.key, required this.label, required this.selected, required this.onTap, this.icon, this.onLongPress});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    final fg = selected ? rv.onInk : rv.text2;
    return Semantics(
      button: true,
      selected: selected,
      child: Pressable(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(color: selected ? rv.ink : Colors.transparent, borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 17, color: fg), const SizedBox(width: 6)],
            Text(label, style: TextStyle(fontFamily: font, fontSize: 16, fontWeight: FontWeight.w600, color: fg)),
          ]),
        ),
      ),
    );
  }
}

/// Custom top bar: round back button, centred title, trailing actions. Same on every platform.
class TopBar extends StatelessWidget implements PreferredSizeWidget {
  const TopBar({super.key, this.title, this.actions = const [], this.back = true});
  final String? title;
  final List<Widget> actions;
  final bool back;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            if (back)
              RoundButton(icon: Icons.arrow_back_ios_new_rounded, tooltip: 'Back', onTap: () => Navigator.maybePop(context))
            else
              const SizedBox(width: 44),
            Expanded(
              child: Text(title ?? '',
                  textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: RvText.headline(rv.text)),
            ),
            if (actions.isEmpty) const SizedBox(width: 44) else ...actions,
          ]),
        ),
      ),
    );
  }
}

/// Raised surface for cards.
BoxDecoration surface(BuildContext context, {double radius = 24}) {
  final rv = Rv.of(context);
  return BoxDecoration(
    color: rv.surface,
    borderRadius: BorderRadius.circular(radius),
    border: rv.dark ? Border.all(color: rv.stroke) : null,
    boxShadow: rv.dark ? null : const [BoxShadow(color: Color(0x0D000000), blurRadius: 20, offset: Offset(0, 6))],
  );
}

/// Thin rounded track with a coloured fill that never shrinks below a dot.
class ProgressTrack extends StatelessWidget {
  const ProgressTrack({super.key, required this.value, required this.color, this.height = 8, this.track});
  final double value; // 0..1
  final Color color;
  final double height;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    final bg = track ?? Rv.of(context).raised;
    return LayoutBuilder(builder: (context, c) {
      final target = (c.maxWidth * value.clamp(0, 1)).clamp(height, c.maxWidth);
      return Container(
        height: height,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(height)),
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: target),
          duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 650),
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

/// Background for a list: its photo, or a soft two-tone gradient of its colour with a light sheen.
class ListCover extends StatelessWidget {
  const ListCover({super.key, required this.store, required this.list, this.child});
  final Store store;
  final RevueList list;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final file = store.listImage(list);
    final base = Color(list.color);
    final hsl = HSLColor.fromColor(base);
    final deep = hsl.withLightness((hsl.lightness * 0.45).clamp(0.08, 0.4)).toColor();
    final light = hsl.withLightness((hsl.lightness * 1.15).clamp(0.3, 0.72)).toColor();
    final photo = file != null && file.existsSync();
    return Stack(fit: StackFit.expand, children: [
      if (photo)
        Image.file(file, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox())
      else
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [deep, light]),
          ),
        ),
      // Scrim so white text stays legible on any photo or colour (photos can be bright, so they get more).
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: photo
                ? const [Color(0x73000000), Color(0x0D000000), Color(0xBF000000)]
                : const [Color(0x26000000), Color(0x00000000), Color(0x8C000000)],
            stops: const [0, 0.4, 1],
          ),
        ),
      ),
      ?child,
    ]);
  }
}

File? coverFile(Store store, RevueList l) => store.listImage(l);

/// Section label above a group ("WATCHING · 3").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.count});
  final String text;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(children: [
        Text(text.toUpperCase(), style: RvText.label(rv.text2)),
        if (count != null) ...[const SizedBox(width: 6), Text('$count', style: RvText.label(rv.text2))],
      ]),
    );
  }
}
