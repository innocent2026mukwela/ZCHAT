import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Brand
  static const primary       = Color(0xFF0057FF);
  static const primaryDark   = Color(0xFF0040CC);
  static const primaryLight  = Color(0xFF4D8AFF);

  // Backgrounds
  static const background    = Color(0xFFF5F7FA);
  static const surface       = Color(0xFFFFFFFF);
  static const splashBg      = Color(0xFF06061A);
  static const splashMid     = Color(0xFF0A1A4A);

  // Text
  static const textDark      = Color(0xFF0A0A23);
  static const textMuted     = Color(0xFF8B92A5);

  // UI
  static const divider       = Color(0xFFE8ECF4);
  static const inputBg       = Color(0xFFF0F3FA);
  static const error         = Color(0xFFFF3B30);
  static const success       = Color(0xFF34C759);

  // Chat
  static const messageSent   = Color(0xFFDCF8C6);
  static const onlineGreen   = Color(0xFF34C759);

  // Feature colours (kept for later screens)
  static const aiPurple      = Color(0xFF7C3AED);
  static const warnOrange    = Color(0xFFF57C00);
  static const secondary     = Color(0xFFFFD700);
}

class AppTheme {
  // Dark theme — the whole app renders on dark gradients, so the base theme is
  // dark. This makes any widget that relies on defaults (text, inputs, cards)
  // look correct on the dark UI instead of leaking white surfaces.
  static const _surfaceDark = Color(0xFF0E1829);
  static const _scaffoldDark = Color(0xFF070F1E);

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor:  AppColors.primary,
      brightness: Brightness.dark,
      primary:    AppColors.primaryLight,
      surface:    _surfaceDark,
      error:      AppColors.error,
    ),
    scaffoldBackgroundColor: _scaffoldDark,
    textTheme: GoogleFonts.interTextTheme(ThemeData(brightness: Brightness.dark).textTheme).apply(
      bodyColor:    Colors.white,
      displayColor: Colors.white,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(
        color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 54),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withAlpha(15), // dark-translucent, never white
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      labelStyle: TextStyle(color: Colors.white.withAlpha(150)),
      hintStyle: TextStyle(color: Colors.white.withAlpha(110)),
    ),
    cardTheme: CardThemeData(
      color: _surfaceDark,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(color: Colors.white.withAlpha(20), thickness: 1),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF0A1330),
      selectedItemColor: AppColors.primaryLight,
      unselectedItemColor: Colors.white54,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
  );
}
