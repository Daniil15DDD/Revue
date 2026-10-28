import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

const _letterAsset = 'assets/brand/splash_letter.png';
const _ribbonAsset = 'assets/brand/splash_ribbon.png';

/// Decode both logo layers before the first frame so nothing blinks while images load.
Future<void> precacheLaunchLogo() => Future.wait([_decode(_letterAsset), _decode(_ribbonAsset)])
    .timeout(const Duration(seconds: 2), onTimeout: () => []);

final _images = <String, ui.Image>{};

Future<void> _decode(String asset) {
  final done = Completer<void>();
  final stream = AssetImage(asset).resolve(ImageConfiguration.empty);
  late final ImageStreamListener l;
  l = ImageStreamListener((info, _) {
    _images[asset] = info.image;
    if (!done.isCompleted) done.complete();
    stream.removeListener(l);
  }, onError: (_, _) {
    if (!done.isCompleted) done.complete();
  });
  stream.addListener(l);
  return done.future;
}

/// Launch animation, from a black screen:
///   1. the r writes itself like a pen stroke — up the stem, round the curve, along the arm,
///   2. the orange bookmark drops out from under the tip on a bouncy spring, with a warm glow,
///   3. a beat, then the logo lifts away as the app settles in underneath.
/// A tap skips to the reveal; Reduce Motion gets a short cross-fade instead.
class LaunchSplash extends StatefulWidget {
  const LaunchSplash({super.key, required this.child});
  final Widget child;

  static const logoSize = 160.0; // logical px

  @override
  State<LaunchSplash> createState() => _LaunchSplashState();
}

class _LaunchSplashState extends State<LaunchSplash> with SingleTickerProviderStateMixin {
  static const _total = Duration(milliseconds: 1800);
  // Timeline (fractions of _total).
  static const _writeStart = 0.12, _writeEnd = 0.48, _dropStart = 0.45, _dropEnd = 0.77, _reveal = 0.81;

  late final AnimationController _c = AnimationController(vsync: this, duration: _total);
  bool _done = false;
  bool _calm = false;

  // Bookmark drop: under-damped spring, from -1 (hidden under the arm) to 0 (hanging).
  final _drop = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: math.pow(2 * math.pi / 0.38, 2).toDouble(), ratio: 0.5),
    -1.2, // fully hidden above the arm's underside
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
      _c.value = _reveal;
    }
    // A status listener, not forward().whenComplete: skipping restarts the controller, which cancels
    // the first forward() future so it would never complete and the splash would stay up.
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _done = true);
    });
    // Start the clock only once the first frame is on screen (the black beat is in the timeline): a cold start
    // stalls the first frames, and a running clock would "draw" the r before anyone sees it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_c.isAnimating && !_c.isCompleted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _skip() {
    if (_c.value < _reveal || !_c.isAnimating) {
      _c
        ..value = _reveal
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
        final reveal = Curves.easeOutCubic.transform(_phase(t, _reveal, 1));
        final write = _calm ? 1.0 : Curves.easeInOutCubic.transform(_phase(t, _writeStart, _writeEnd));
        final dropSecs = _phase(t, _dropStart, _dropEnd) * _total.inMilliseconds * (_dropEnd - _dropStart) / 1000;
        final ribbon = _calm || t >= _dropEnd ? 0.0 : (t < _dropStart ? -1.2 : _drop.x(dropSecs));
        final glow = _calm
            ? 0.35
            : 0.35 * _phase(t, _dropStart, _dropStart + 0.08) + 0.65 * math.sin(math.pi * _phase(t, _dropStart + 0.06, _dropEnd));

        return Stack(fit: StackFit.expand, children: [
          Opacity(
            opacity: reveal,
            child: Transform.scale(scale: 0.96 + 0.04 * reveal, child: widget.child),
          ),
          if (reveal < 1)
            GestureDetector(
              key: const ValueKey('launch-splash'),
              behavior: HitTestBehavior.opaque,
              onTap: _skip,
              child: Opacity(
                opacity: 1 - reveal,
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Transform.scale(
                      scale: 1 + 0.22 * reveal, // lifts toward the viewer as it leaves
                      child: SizedBox.square(
                        dimension: LaunchSplash.logoSize,
                        child: CustomPaint(painter: _LogoPainter(write: write, ribbon: ribbon, glow: glow)),
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
}

/// Paints the logo on its 1024-unit canvas: the letter revealed along its pen path, then the ribbon.
class _LogoPainter extends CustomPainter {
  _LogoPainter({required this.write, required this.ribbon, required this.glow});
  final double write; // 0..1 of the stroke drawn
  final double ribbon; // ribbon offset in ribbon-heights; -1.2 = hidden under the arm, 0 = hanging
  final double glow; // 0..1

  // Geometry measured from the artwork (1024 canvas): stroke 128 wide, stem centre x 345.5,
  // corner centred (510, 460) with centre-line radius 164.5, arm centre y 295.5.
  static final Path _pen = Path()
    ..moveTo(345.5, 770)
    ..lineTo(345.5, 460)
    ..arcToPoint(const Offset(510, 295.5), radius: const Radius.circular(164.5))
    ..lineTo(770, 295.5);
  static const _ribbon = Rect.fromLTRB(623, 375, 746, 525);
  static const _armUnderside = 352.0; // the ribbon emerges from below here

  @override
  void paint(Canvas canvas, Size size) {
    final letter = _images[_letterAsset], ribbonImg = _images[_ribbonAsset];
    if (letter == null || ribbonImg == null) return;
    canvas.scale(size.width / 1024);
    const full = Rect.fromLTWH(0, 0, 1024, 1024);
    final src = Rect.fromLTWH(0, 0, letter.width.toDouble(), letter.height.toDouble());
    final paint = Paint()..filterQuality = FilterQuality.high;

    // Warm glow behind the ribbon.
    if (glow > 0) {
      final c = _ribbon.center.translate(0, ribbon * _ribbon.height);
      canvas.drawCircle(
          c,
          150,
          Paint()
            ..color = const Color(0xFFFF8A4C).withValues(alpha: 0.45 * glow)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70));
    }

    // Ribbon: drops out from under the arm (clipped above the arm's underside).
    if (ribbon > -1.2) {
      canvas.save();
      canvas.clipRect(const Rect.fromLTRB(0, _armUnderside, 1024, 1024));
      canvas.translate(0, ribbon * _ribbon.height);
      canvas.drawImageRect(ribbonImg, src, full, paint);
      canvas.restore();
    }

    // Letter: the real artwork, revealed by a soft-edged stroke that follows the pen path.
    if (write > 0) {
      canvas.saveLayer(full, Paint());
      canvas.drawImageRect(letter, src, full, paint);
      final metric = _pen.computeMetrics().first;
      final drawn = metric.extractPath(0, metric.length * write);
      // The mask goes in its own layer, composited with dstIn as a whole: a dstIn draw call would
      // only touch pixels under the path and leave the rest of the letter visible.
      canvas.saveLayer(full, Paint()..blendMode = BlendMode.dstIn);
      canvas.drawPath(
          drawn,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 196 // covers the 128 stroke, its round end and the tip's lower edge
            ..strokeCap = write < 1 ? StrokeCap.round : StrokeCap.square
            ..maskFilter = write < 1 ? const MaskFilter.blur(BlurStyle.normal, 5) : null);
      canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.write != write || old.ribbon != ribbon || old.glow != glow;
}
