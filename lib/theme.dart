import 'package:flutter/material.dart';

/// Serif for headings: Georgia on iOS, Noto Serif ("serif") on Android.
const serif = TextStyle(fontFamily: 'Georgia', fontFamilyFallback: ['serif', 'Noto Serif']);

ThemeData revueTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFB4532A), // burnt orange
    brightness: b,
    surface: dark ? const Color(0xFF15120F) : const Color(0xFFFAF6F0),
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.merge(serif).copyWith(fontWeight: FontWeight.w600),
      headlineMedium: base.textTheme.headlineMedium?.merge(serif).copyWith(fontWeight: FontWeight.w600),
      headlineSmall: base.textTheme.headlineSmall?.merge(serif).copyWith(fontWeight: FontWeight.w600),
      titleLarge: base.textTheme.titleLarge?.merge(serif),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: dark ? const Color(0xFF221D19) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: base.chipTheme.copyWith(shape: const StadiumBorder()),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: scheme.surface, elevation: 0),
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent),
  );
}
