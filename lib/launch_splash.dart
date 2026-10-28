import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Launch animation over the app's first frame. Starts exactly like the native splash
/// (logo on black, 160 pt), so the handoff is invisible:
///   1. the bookmark is tugged up into the r's arm while the r presses in slightly,
///   2. it drops back with a spring bounce and the glow lights up,
///   3. the logo lifts away as the home screen fades and settles in underneath.
/// A tap skips straight to the reveal; Reduce Motion gets a short cross-fade instead.
/// Decode both logo layers before the first frame so the splash never blinks while images load.
Future<void> precacheLaunchLogo() => Future.wait([
      for (final a in const ['assets/brand/splash_letter.png', 'assets/brand/splash_ribbon.png']) _decode(AssetImage(a)),
    ]).timeout(const Duration(seconds: 2), onTimeout: () => []);

Future<void> _decode(ImageProvider p) {
  final done = Completer<void>();
  final stream = p.resolve(ImageConfiguration.empty);
  late final ImageStreamListener l;
  l = ImageStreamListener((_, _) {
    if (!done.isCompleted) done.complete();
    stream.removeListener(l);
  }, onError: (_, _) {
    if (!done.isCompleted) done.complete();
  });
  stream.addListener(l);
  return done.future;
}

class LaunchSplash extends StatefulWidget {
  const LaunchSplash({super.key, required this.child});
  final Widget child;

  static const logoSize = 160.0; // logical px; matches the native splash bitmap

  @override
  State<LaunchSplash> createState() => _LaunchSplashState();
}

class _LaunchSplashState extends State<LaunchSplash> with SingleTickerProviderStateMixin {
  static const _total = Duration(milliseconds: 1250);
  // Phase boundaries as fractions of _total.
  static const _tugEnd = 0.22, _dropEnd = 0.66;

  late final AnimationController _c = AnimationController(vsync: this, duration: _total);
  bool _done = false;
  bool _calm = false;

  // Bookmark drop: under-damped spring (it was "thrown"), from -1 (tucked up) to 0 (resting).
  final _drop = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: math.pow(2 * math.pi / 0.34, 2).toDouble(), ratio: 0.55),
    -1,
    0,
    0,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted || _done) return;
    _calm = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_calm) {
      _c.duration = const Duration(milliseconds: 280);
      _c.value = _dropEnd; // straight to the reveal
    }
    // A status listener, not forward().whenComplete: skipping restarts the controller, which cancels
    // the first forward() future so it would never complete and the splash would stay up.
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _done = true);
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _skip() {
    if (_c.value < _dropEnd) {
      _c
        ..value = _dropEnd
        ..forward();
    }
  }

  double _phase(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final reveal = Curves.easeOutCubic.transform(_phase(t, _dropEnd, 1));
        // Ribbon offset in "ribbon heights": up during the tug, spring back down during the drop.
        final tug = Curves.easeInOutCubic.transform(_phase(t, 0, _tugEnd));
        final dropT = _phase(t, _tugEnd, _dropEnd) * (_total.inMilliseconds * (_dropEnd - _tugEnd) / 1000);
        final ribbonY = t < _tugEnd ? -0.85 * tug : 0.85 * _drop.x(dropT);
        // The r presses in a touch while the ribbon is pulled, and releases as it lands.
        final press = t < _tugEnd ? 1 - 0.05 * tug : 0.95 + 0.05 * Curves.easeOutBack.transform(_phase(t, _tugEnd, _dropEnd * 0.9));
        // Glow flares as the ribbon lands, then eases back to the logo's resting glow.
        final land = _phase(t, _tugEnd + 0.12, _dropEnd);
        final glow = 0.35 + 0.65 * math.sin(math.pi * land);

        return Stack(fit: StackFit.expand, children: [
          // The app, settling in underneath.
          Opacity(
            opacity: reveal,
            child: Transform.scale(scale: 0.96 + 0.04 * reveal, child: widget.child),
          ),
          if (reveal < 1)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _skip,
              child: Opacity(
                opacity: 1 - reveal,
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Transform.scale(
                      scale: (_calm ? 1 : press) * (1 + 0.25 * reveal), // lifts toward the viewer as it leaves
                      child: _Logo(ribbonY: _calm ? 0 : ribbonY, glow: _calm ? 0.35 : glow),
                    ),
                  ),
                ),
              ),
            ),
        ]);
      },
    );
  }
}

/// The logo built from its two layers on a 1024-unit canvas, drawn at [LaunchSplash.logoSize].
class _Logo extends StatelessWidget {
  const _Logo({required this.ribbonY, required this.glow});
  final double ribbonY; // in ribbon heights; negative = tucked up into the arm
  final double glow; // 0..1

  // Ribbon bounds on the 1024 canvas (from the artwork).
  static const _rx = 623.0, _ry = 375.0, _rw = 123.0, _rh = 150.0, _armTop = 236.0;

  @override
  Widget build(BuildContext context) {
    const size = LaunchSplash.logoSize;
    const k = size / 1024;
    return SizedBox.square(
      dimension: size,
      child: Stack(clipBehavior: Clip.none, children: [
        // Warm glow behind the ribbon.
        Positioned(
          left: (_rx + _rw / 2) * k - 40,
          top: (_ry + _rh / 2 + ribbonY * _rh) * k - 40,
          child: IgnorePointer(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: const Color(0xFFFF8A4C).withValues(alpha: 0.55 * glow), blurRadius: 28, spreadRadius: 2)],
              ),
            ),
          ),
        ),
        // Ribbon slides under the arm: clip anything above the arm's top edge.
        Positioned.fill(
          child: ClipRect(
            clipper: const _BelowY(_armTop * k),
            child: Transform.translate(
              offset: Offset(0, ribbonY * _rh * k),
              child: Image.asset('assets/brand/splash_ribbon.png', width: size, height: size, filterQuality: FilterQuality.high),
            ),
          ),
        ),
        Image.asset('assets/brand/splash_letter.png', width: size, height: size, filterQuality: FilterQuality.high),
      ]),
    );
  }
}

class _BelowY extends CustomClipper<Rect> {
  const _BelowY(this.y);
  final double y;
  @override
  Rect getClip(Size size) => Rect.fromLTRB(-size.width, y, size.width * 2, size.height * 2);
  @override
  bool shouldReclip(_BelowY old) => old.y != y;
}
