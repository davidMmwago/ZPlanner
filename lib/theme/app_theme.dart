// ─────────────────────────────────────────────────────────────
// ALL STYLING LIVES HERE.
// When you're ready to stylise the app, this is the file to change:
// colours, fonts, corner radius, spacing, module + ink colours.
// ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

class AppPalette {
  // Core colours (placeholder neutral look — swap these for the real style)
  static const Color seed = Color(0xFF7C6FD6);
  static const Color background = Color(0xFFF7F5F2);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF1F1D2B);
  static const Color muted = Color(0xFF8A8797);
  static const Color paper = Color(0xFFFFFEFB);
  static const Color paperLine = Color(0xFFDDE3EE);
  static const Color paperMargin = Color(0xFFF2C4C4);

  // Mascot
  static const Color ghostFill = Color(0xFFFFFFFF);
  static const Color ghostLine = Color(0xFF1B1B1B);
  static const Color bubble = Color(0xFFFFFFFF);

  // Charts (single-hue bars) and money in/out
  static const Color chart = Color(0xFF7C6FD6);
  static const Color chartMuted = Color(0xFFD9D4F5);
  static const Color moneyIn = Color(0xFF2E8B6A);
  static const Color moneyOut = Color(0xFFC0504D);

  // Colours a module can be given
  static const List<Color> moduleColors = [
    Color(0xFF7C6FD6),
    Color(0xFFE88D8D),
    Color(0xFF6FB7A8),
    Color(0xFFF2B35B),
    Color(0xFF5B8DEF),
    Color(0xFFD67CB5),
    Color(0xFF8BAA5A),
    Color(0xFF9A7B6A),
  ];

  // Pen colours in the drawing toolbar
  static const List<Color> penColors = [
    Color(0xFF1F1D2B),
    Color(0xFF2F5BD3),
    Color(0xFFD33F49),
    Color(0xFF2E9E6A),
    Color(0xFF8E44AD),
  ];

  // Highlighter colours (alpha is applied automatically)
  static const List<Color> highlighterColors = [
    Color(0xFFFFE14D),
    Color(0xFF7CF0A0),
    Color(0xFFFF9EC7),
    Color(0xFF7FD8FF),
  ];
}

/// Personal bits. Change these to whatever you like.
class AppConfig {
  static const String herName = 'Zee';
  static const String mascotName = 'Boo';
  static const String currency = 'R';

  /// Used for reminders if the tablet's time zone can't be read.
  static const String timeZone = 'Africa/Johannesburg';

  /// Google sign-in (see README → "Google setup"). Paste your iOS-type
  /// OAuth client ID here, e.g. '1234-abcd.apps.googleusercontent.com'.
  static const String googleClientId = '910111650029-a6mvv6ppn81fci3747h0utsamcfrk6ru.apps.googleusercontent.com';
}

class AppShape {
  static const double radius = 18;
  static const double radiusSmall = 10;
  static BorderRadius get card => BorderRadius.circular(radius);
}

class AppSpace {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppPalette.seed,
      surface: AppPalette.surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppPalette.background,
      // fontFamily: 'YourFontHere', // add a font in pubspec.yaml later
      appBarTheme: const AppBarTheme(
        backgroundColor: AppPalette.background,
        foregroundColor: AppPalette.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppPalette.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppShape.card),
        margin: EdgeInsets.zero,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShape.radius)),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppPalette.background,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppShape.radiusSmall)),
      ),
    );
  }
}
