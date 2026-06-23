import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'webey_colors.dart';

class WebeyTheme {
  const WebeyTheme._();

  static ThemeData customer() => _luxury();
  static ThemeData business() => _luxury();

  static ThemeData _luxury() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: WebeyColors.primaryGold,
      onPrimary: WebeyColors.darkEspresso,
      secondary: WebeyColors.deepChampagne,
      onSecondary: WebeyColors.darkEspresso,
      surface: WebeyColors.warmCream,
      onSurface: WebeyColors.darkEspresso,
      error: WebeyColors.errorRed,
      onError: WebeyColors.softWhite,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: WebeyColors.ivory,

      appBarTheme: AppBarTheme(
        backgroundColor: WebeyColors.ivory,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: WebeyColors.darkEspresso,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: const TextStyle(
          color: WebeyColors.darkEspresso,
          fontSize: 18,
          fontWeight: FontWeight.w500,
          fontFamily: 'Georgia',
          letterSpacing: 0.3,
        ),
        iconTheme: const IconThemeData(color: WebeyColors.darkEspresso),
        actionsIconTheme: const IconThemeData(color: WebeyColors.darkEspresso),
        shape: const Border(bottom: BorderSide(color: WebeyColors.borderSand)),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        backgroundColor: WebeyColors.softWhite,
        selectedItemColor: WebeyColors.primaryGold,
        unselectedItemColor: WebeyColors.mutedTaupe,
        showUnselectedLabels: true,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),

      cardTheme: CardThemeData(
        color: WebeyColors.warmCream,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WebeyRadius.medium),
          side: const BorderSide(color: WebeyColors.borderSand),
        ),
        shadowColor: WebeyColors.alpha(WebeyColors.darkEspresso, 0.06),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: WebeyColors.goldLight,
        selectedColor: WebeyColors.blushRose,
        checkmarkColor: WebeyColors.primaryGold,
        labelStyle: const TextStyle(
          color: WebeyColors.mutedTaupe,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WebeyRadius.small),
          side: const BorderSide(color: WebeyColors.borderSand),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WebeyColors.ivory,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebeyRadius.small),
          borderSide: const BorderSide(color: WebeyColors.borderSand),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebeyRadius.small),
          borderSide: const BorderSide(color: WebeyColors.borderSand),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebeyRadius.small),
          borderSide: const BorderSide(
            color: WebeyColors.primaryGold,
            width: 1.4,
          ),
        ),
        hintStyle: const TextStyle(color: WebeyColors.mutedTaupe, fontSize: 14),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: WebeyColors.primaryGold,
          foregroundColor: WebeyColors.darkEspresso,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebeyRadius.small),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 1.5,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: WebeyColors.darkEspresso,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: WebeyColors.borderSand),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebeyRadius.small),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 1.0,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: WebeyColors.primaryGold,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: WebeyColors.borderSand,
        thickness: 1,
        space: 1,
      ),

      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: WebeyColors.darkEspresso,
          fontSize: 32,
          fontFamily: 'Georgia',
          fontWeight: FontWeight.w300,
          height: 1.1,
          letterSpacing: 0,
        ),
        headlineLarge: TextStyle(
          color: WebeyColors.darkEspresso,
          fontSize: 24,
          fontFamily: 'Georgia',
          fontWeight: FontWeight.w400,
          height: 1.2,
          letterSpacing: 0,
        ),
        headlineMedium: TextStyle(
          color: WebeyColors.darkEspresso,
          fontSize: 20,
          fontFamily: 'Georgia',
          fontWeight: FontWeight.w400,
          height: 1.25,
          letterSpacing: 0,
        ),
        titleLarge: TextStyle(
          color: WebeyColors.darkEspresso,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        titleMedium: TextStyle(
          color: WebeyColors.darkEspresso,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        bodyLarge: TextStyle(
          color: WebeyColors.mutedTaupe,
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.5,
          letterSpacing: 0,
        ),
        bodyMedium: TextStyle(
          color: WebeyColors.mutedTaupe,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.4,
          letterSpacing: 0,
        ),
        labelLarge: TextStyle(
          color: WebeyColors.darkEspresso,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
        labelMedium: TextStyle(
          color: WebeyColors.mutedTaupe,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
