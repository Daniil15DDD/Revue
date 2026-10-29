import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Revue's own look: the same on iPhone and Android. Black-and-ink, big soft radii, one warm accent.
const font = 'Figtree';
const serif = TextStyle(fontFamily: font); // kept for older call sites

/// Design tokens. Read with `Rv.of(context)`.
@immutable
class Rv extends ThemeExtension<Rv> {
  const Rv({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.stroke,
    required this.text,
    required this.text2,
    required this.text3,
    required this.ink,
    required this.onInk,
    required this.accent,
    required this.glass,
    required this.dark,
  });

  final Color bg; // page
  final Color surface; // cards
  final Color raised; // fields, pills, chips on cards
  final Color stroke; // hairlines
  final Color text, text2, text3; // primary / secondary / tertiary text
  final Color ink, onInk; // primary pill buttons: white on black, black on white
  final Color accent; // progress, highlights
  final Color glass; // translucent bars and sheets (over a blur)
  final bool dark;

  static const darkTokens = Rv(
    bg: Color(0xFF000000),
    surface: Color(0xFF161618),
    raised: Color(0xFF242427),
    stroke: Color(0x1FFFFFFF),
    text: Color(0xFFF5F5F7),
    text2: Color(0x99F5F5F7),
    text3: Color(0x66F5F5F7), // icons only: 3:1 on raised; text uses text2 (4.5:1)
    ink: Color(0xFFFFFFFF),
    onInk: Color(0xFF000000),
    accent: Color(0xFFFF8A4C),
    glass: Color(0xB81C1C1E),
    dark: true,
  );

  static const lightTokens = Rv(
    bg: Color(0xFFF2F1EE),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFEAE8E4),
    stroke: Color(0x14000000),
    text: Color(0xFF111111),
    text2: Color(0x99111111),
    text3: Color(0x73111111), // icons only: 3:1 on white; text uses text2 (4.5:1)
    ink: Color(0xFF111111),
    onInk: Color(0xFFFFFFFF),
    accent: Color(0xFFC24A16), // 4.9:1 on white, so it works as small text
    glass: Color(0xC7FFFFFF),
    dark: false,
  );

  static Rv of(BuildContext context) => Theme.of(context).extension<Rv>()!;

  @override
  Rv copyWith() => this;

  @override
  Rv lerp(Rv? other, double t) => t < 0.5 ? this : (other ?? this);
}

/// Type scale: tight tracking on big text, neutral on body (size-specific, never one value).
class RvText {
  static TextStyle display(Color c) =>
      TextStyle(fontFamily: font, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.0, height: 1.05, color: c);
  static TextStyle title(Color c) =>
      TextStyle(fontFamily: font, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.6, height: 1.1, color: c);
  static TextStyle headline(Color c) =>
      TextStyle(fontFamily: font, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.2, color: c);
  static TextStyle body(Color c) => TextStyle(fontFamily: font, fontSize: 16, fontWeight: FontWeight.w500, height: 1.35, color: c);
  static TextStyle small(Color c) =>
      TextStyle(fontFamily: font, fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.1, height: 1.3, color: c);
  static TextStyle label(Color c) =>
      TextStyle(fontFamily: font, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c);
}

ThemeData revueTheme(Brightness b, TargetPlatform platform) {
  final rv = b == Brightness.dark ? Rv.darkTokens : Rv.lightTokens;
  final scheme = ColorScheme.fromSeed(seedColor: rv.accent, brightness: b).copyWith(
    primary: rv.accent,
    onPrimary: Colors.white,
    surface: rv.bg,
    onSurface: rv.text,
    onSurfaceVariant: rv.text2,
    surfaceContainerHighest: rv.raised,
    primaryContainer: rv.raised,
    onPrimaryContainer: rv.text2,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, platform: platform, fontFamily: font);
  return base.copyWith(
    extensions: [rv],
    scaffoldBackgroundColor: rv.bg,
    splashFactory: NoSplash.splashFactory, // feedback is our own press-scale, not ink ripples
    highlightColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(cursorColor: rv.accent, selectionColor: rv.accent.withValues(alpha: 0.3)),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: rv.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: rv.ink,
      contentTextStyle: TextStyle(fontFamily: font, color: rv.onInk, fontWeight: FontWeight.w600),
      shape: const StadiumBorder(),
      insetPadding: const EdgeInsets.fromLTRB(24, 0, 24, 110),
    ),
    appBarTheme: AppBarTheme(backgroundColor: rv.bg, surfaceTintColor: Colors.transparent, foregroundColor: rv.text),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: b,
      primaryColor: rv.accent,
      scaffoldBackgroundColor: rv.bg,
      textTheme: const CupertinoTextThemeData(textStyle: TextStyle(fontFamily: font)),
    ),
  );
}
