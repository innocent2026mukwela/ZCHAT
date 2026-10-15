import 'package:flutter/material.dart';
import 'glass.dart';

/// Campus-product palette: deep navy surfaces, restrained UnZA blue accents.
/// Avoids purple glow / generic “AI SaaS” gradients.
class AppColors {
  // Brand
  static const primary       = Color(0xFF1A6BE0);
  static const primaryDark   = Color(0xFF1456B8);
  static const primaryLight  = Color(0xFF5B9BFF);

  // Backgrounds
  static const background    = Color(0xFF0A1220);
  static const surface       = Color(0xFF121C2E);
  static const splashBg      = Color(0xFF070D18);
  static const splashMid     = Color(0xFF0C1628);

  // Text
  static const textDark      = Color(0xFF0A0A23);
  static const textMuted     = Color(0xFF8B92A5);

  // UI
  static const divider       = Color(0xFF1E2A3E);
  static const inputBg       = Color(0xFF152033);
  static const error         = Color(0xFFE5484D);
  static const success       = Color(0xFF2F9E44);

  // Chat
  static const messageSent   = Color(0xFF1A3A2A);
  static const onlineGreen   = Color(0xFF2F9E44);

  // Feature accents (restrained — no purple glow)
  static const aiAccent      = Color(0xFF3D7DD6);
  static const warnOrange    = Color(0xFFE67700);
  static const secondary     = Color(0xFFC9A227);

  @Deprecated('Use aiAccent — purple glow removed from visual language')
  static const aiPurple      = aiAccent;
}

class AppTheme {
  static const _surfaceDark = Color(0xFF121C2E);
  static const _scaffoldDark = Color(0xFF0A1220);

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: kBrandFont,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primaryLight,
      onPrimary: Colors.white,
      secondary: AppColors.primary,
      surface: _surfaceDark,
      error: AppColors.error,
      onSurface: Colors.white,
    ),
    scaffoldBackgroundColor: _scaffoldDark,
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontFamily: kBrandFont, color: Colors.white),
      bodyMedium: TextStyle(fontFamily: kBrandFont, color: Colors.white),
      titleLarge: TextStyle(fontFamily: kBrandFont, color: Colors.white, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontFamily: kBrandFont, color: Colors.white, fontWeight: FontWeight.w600),
      labelLarge: TextStyle(fontFamily: kBrandFont, color: Colors.white, fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kBrandFont,
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: kBrandFont,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withAlpha(12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      labelStyle: TextStyle(color: Colors.white.withAlpha(150)),
      hintStyle: TextStyle(color: Colors.white.withAlpha(110)),
    ),
    cardTheme: CardThemeData(
      color: _surfaceDark,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: Colors.white.withAlpha(18), thickness: 1),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF0C1524),
      selectedItemColor: AppColors.primaryLight,
      unselectedItemColor: Colors.white54,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
  );
}
