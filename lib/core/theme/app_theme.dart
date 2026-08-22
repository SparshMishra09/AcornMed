import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color sage = Color(0xFF8D9771);
  static const Color sageDark = Color(0xFF6E7856);
  static const Color sageDeep = Color(0xFF576143);
  static const Color sageLight = Color(0xFFE9ECE0);
  static const Color sagePale = Color(0xFFF5F6F0);
  static const Color cream = Color(0xFFFDFBF4);

  static const Color mustard = Color(0xFFF1BE3B);
  static const Color mustardDark = Color(0xFFD9A520);
  static const Color mustardPale = Color(0xFFFBEFD0);

  static const Color coffee = Color(0xFF4A2C18);
  static const Color coffeeSoft = Color(0xFF6B4A33);
  static const Color acorn = Color(0xFF764B29);

  static const Color outlineSoft = Color(0xFFDDE4D6);

  static const Color error = Color(0xFFB3402F);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final scheme = const ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.sageDark,
      onPrimary: Colors.white,
      primaryContainer: AppColors.sageLight,
      onPrimaryContainer: AppColors.sageDeep,
      secondary: AppColors.mustard,
      onSecondary: AppColors.coffee,
      secondaryContainer: AppColors.mustardPale,
      onSecondaryContainer: AppColors.acorn,
      tertiary: AppColors.acorn,
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFEAD9C8),
      onTertiaryContainer: AppColors.coffee,
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: Color(0xFFF9DEDC),
      onErrorContainer: Color(0xFF410E0B),
      surface: AppColors.cream,
      onSurface: AppColors.coffee,
      surfaceContainerHighest: AppColors.sagePale,
      onSurfaceVariant: AppColors.coffeeSoft,
      outline: Color(0xFFC3CCBB),
      outlineVariant: Color(0xFFDDE4D6),
      shadow: Color(0x1F4A2C18),
      scrim: Color(0x664A2C18),
      inverseSurface: AppColors.coffee,
      onInverseSurface: AppColors.cream,
      inversePrimary: Color(0xFFB9C7AC),
      surfaceTint: AppColors.sageDark,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.sagePale,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.sagePale,
        foregroundColor: AppColors.coffee,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.coffee,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.outlineSoft),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.sageDark,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.sageDeep,
          side: const BorderSide(color: AppColors.sage),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.sageDeep,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.outlineSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.sage, width: 1.6),
        ),
        hintStyle: const TextStyle(color: AppColors.coffeeSoft),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: Colors.white,
        selectedColor: AppColors.mustardPale,
        side: const BorderSide(color: AppColors.outlineSoft),
        labelStyle: const TextStyle(
          color: AppColors.coffee,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outlineSoft,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.coffee,
        contentTextStyle: const TextStyle(color: AppColors.cream),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cream,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: const TextStyle(
          color: AppColors.coffee,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.coffeeSoft,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.cream,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.sageDeep,
        textColor: AppColors.coffee,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.sageDark,
        linearTrackColor: AppColors.sageLight,
        circularTrackColor: AppColors.sageLight,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.coffee,
        displayColor: AppColors.coffee,
      ),
    );
  }
}
