import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();
  static const maroon = Color(0xFF7A1F1F);
  static const maroonSoft = Color(0xFF8F2B27);
  static const saffron = Color(0xFFE8890C);
  static const gold = Color(0xFFF6C58A);
  static const ground = Color(0xFFFFF7EC);
  static const ink = Color(0xFF3A1512);
  static const muted = Color(0xFF7A5A50);
  static const line = Color(0xFFF0DCC4);
  static const green = Color(0xFF2F5420);
  static const greenBg = Color(0xFFE3EED9);
  static const amber = Color(0xFF8A4300);
  static const amberBg = Color(0xFFFDE7C8);
  static const red = Color(0xFF8E1C1C);
  static const redBg = Color(0xFFF7D9D5);
  static const blue = Color(0xFF25528A);
  static const blueBg = Color(0xFFDDE7F3);
  static const purple = Color(0xFF6B2D73);
  static const purpleBg = Color(0xFFEEDDF0);
}

/// Display font (headings, amounts).
TextStyle display(double size, {Color color = AppColors.ink}) =>
    GoogleFonts.baloo2(fontSize: size, fontWeight: FontWeight.w700, color: color, height: 1.15);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.maroon,
      primary: AppColors.maroon,
      secondary: AppColors.saffron,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: AppColors.ground,
  );
  final text = GoogleFonts.muktaTextTheme(base.textTheme)
      .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AppColors.line),
  );

  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.ground,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.baloo2(
          fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.maroon, width: 1.6)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.maroon,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.maroon,
        minimumSize: const Size(0, 44),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.saffron,
      foregroundColor: AppColors.ink,
    ),
    chipTheme: base.chipTheme.copyWith(
      side: const BorderSide(color: AppColors.line),
      backgroundColor: Colors.white,
      selectedColor: AppColors.ink,
      labelStyle: const TextStyle(color: AppColors.ink),
      secondaryLabelStyle: const TextStyle(color: Colors.white),
      checkmarkColor: Colors.white,
    ),
  );
}
