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
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary:   AppColors.primary,
      surface:   AppColors.surface,
      error:     AppColors.error,
    ),
    scaffoldBackgroundColor: AppColors.background,
    textTheme: GoogleFonts.interTextTheme().apply(
      bodyColor:    AppColors.textDark,
      displayColor: AppColors.textDark,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.primary,
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
      fillColor: AppColors.inputBg,
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
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      labelStyle: const TextStyle(color: AppColors.textMuted),
      hintStyle: const TextStyle(color: AppColors.textMuted),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textMuted,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
  );
}
