import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Serif for Android headings: Noto Serif ("serif"). iPhone uses the system SF font.
const serif = TextStyle(fontFamily: 'Georgia', fontFamilyFallback: ['serif', 'Noto Serif']);

const _accentLight = Color(0xFFB4532A); // burnt orange
const _accentDark = Color(0xFFE2774A); // brighter, so it reads on black

ThemeData revueTheme(Brightness b, TargetPlatform platform) {
  final dark = b == Brightness.dark;
  final ios = platform == TargetPlatform.iOS;
  final accent = dark ? _accentDark : _accentLight;
  // iOS system grouped colours (Settings, Notes…): F2F2F7/white in light, black/1C1C1E in dark.
  final background = ios
      ? (dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7))
      : (dark ? const Color(0xFF15120F) : const Color(0xFFFAF6F0));
  final card = ios
      ? (dark ? const Color(0xFF1C1C1E) : Colors.white)
      : (dark ? const Color(0xFF221D19) : Colors.white);
  final scheme = ColorScheme.fromSeed(seedColor: _accentLight, brightness: b, surface: background)
      .copyWith(primary: ios ? accent : null, onPrimary: ios ? Colors.white : null);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, platform: platform);
  return base.copyWith(
    scaffoldBackgroundColor: background,
    splashFactory: ios ? NoSplash.splashFactory : null, // no Android ink ripples on iPhone
    textTheme: ios
        ? base.textTheme
        : base.textTheme.copyWith(
            displaySmall: base.textTheme.displaySmall?.merge(serif).copyWith(fontWeight: FontWeight.w600),
            headlineMedium: base.textTheme.headlineMedium?.merge(serif).copyWith(fontWeight: FontWeight.w600),
            headlineSmall: base.textTheme.headlineSmall?.merge(serif).copyWith(fontWeight: FontWeight.w600),
            titleLarge: base.textTheme.titleLarge?.merge(serif),
          ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ios ? 14 : 16)),
    ),
    chipTheme: base.chipTheme.copyWith(shape: const StadiumBorder()),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: background, elevation: 0),
    appBarTheme: AppBarTheme(backgroundColor: background, surfaceTintColor: Colors.transparent),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: b,
      primaryColor: accent,
      scaffoldBackgroundColor: background,
      barBackgroundColor: background.withValues(alpha: 0.85),
    ),
  );
}
