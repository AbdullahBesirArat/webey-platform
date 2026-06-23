import 'package:flutter/material.dart';

class WebeyColors {
  const WebeyColors._();

  // ── Primary luxury palette ─────────────────────────────────────────────────
  static const primaryGold = Color(0xFFB8964E);
  static const deepChampagne = Color(0xFFC9A96E);
  static const ivory = Color(0xFFFAF6F0);
  static const warmCream = Color(0xFFF2EBE0);
  static const darkEspresso = Color(0xFF1C1209);
  static const mutedTaupe = Color(0xFF9C8E82);
  static const blushRose = Color(0xFFE8C4C4);
  static const softWhite = Color(0xFFFAF8F5);
  static const borderSand = Color(0xFFE8DFD4);
  static const successGreen = Color(0xFF4CAF7D);
  static const errorRed = Color(0xFFD84040);
  static const goldLight = Color(0xFFF5EDD8);
  static const warning = Color(0xFFE09B3C);

  // ── Backward-compat aliases ────────────────────────────────────────────────
  static const primaryRose = primaryGold;
  static const softPink = blushRose;
  static const softGold = deepChampagne;
  static const darkText = darkEspresso;
  static const mutedMauve = mutedTaupe;
  static const mutedText = mutedTaupe;
  static const white = softWhite;
  static const surface = warmCream;
  static const lightBorder = borderSand;
  static const stone = goldLight;
  static const nude = goldLight;
  static const espresso = darkEspresso;
  static const success = successGreen;
  static const error = errorRed;
  static const businessInk = darkEspresso;
  static const businessSurface = ivory;
  static const gold = primaryGold;

  static Color alpha(Color color, double opacity) =>
      color.withAlpha((opacity.clamp(0.0, 1.0) * 255).round());
}

class WebeySpacing {
  const WebeySpacing._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
}

class WebeyRadius {
  const WebeyRadius._();

  static const double small = 12;
  static const double medium = 18;
  static const double large = 24;
  static const double pill = 999;
}

class WebeyShadow {
  const WebeyShadow._();

  static List<BoxShadow> get soft => [
    BoxShadow(
      blurRadius: 22,
      offset: const Offset(0, 10),
      color: WebeyColors.alpha(WebeyColors.darkEspresso, 0.07),
    ),
  ];

  static List<BoxShadow> get subtle => [
    BoxShadow(
      blurRadius: 14,
      offset: const Offset(0, 6),
      color: WebeyColors.alpha(WebeyColors.darkEspresso, 0.05),
    ),
  ];
}
