import 'dart:ui';

import 'package:flutter/material.dart';

class ChartTheme {
  ChartTheme._();

  static const Color background = Color(0xFF0A0F16);
  static const Color cardBackground = Color(0xFF121A23);
  static const Color surface2 = Color(0xFF192330);
  static const Color border = Color(0xFF243142);
  static const Color borderSubtle = Color(0xFF1A2531);
  static const Color surfaceHover = Color(0xFF1E2B39);
  static const Color gridLine = Color(0x1EFFFFFF);
  static const Color chartDivider = Color(0xFF1A2531);
  static const Color textPrimary = Color(0xFFF5F7FA);
  static const Color textSecondary = Color(0xFFA8B6C7);
  static const Color textTertiary = Color(0xFF718298);
  static const Color up = Color(0xFF24C07A);
  static const Color down = Color(0xFFFF5B5B);
  static const Color accentGold = Color(0xFFFFC857);
  static const Color tabSelectedBg = Color(0xFF243244);
  static const Color tabUnderline = Color(0xFFFFC857);
  static const Color volumeUp = Color(0xFF4B89FF);
  static const Color avgLine = Color(0xFFFFB648);
  static const Color panelShadow = Color(0x66050A10);

  static const double topBarHeight = 72.0;
  static const double radiusCard = 18.0;
  static const double radiusButton = 12.0;
  static const double pagePadding = 16.0;
  static const double sectionGap = 14.0;
  static const double innerPadding = 14.0;
  static const double toolbarButtonHeight = 36.0;
  static const double toolbarSpacing = 10.0;

  static const double fontSizePrice = 22.0;
  static const double fontSizeKey = 14.0;
  static const double fontSizeAxis = 12.0;
  static const double fontSizeLabel = 11.0;

  static const String fontMono = 'monospace';
  static const FontFeature tabularFigures = FontFeature.tabularFigures();

  static String formatPrice(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 100) return v.toStringAsFixed(2);
    if (v >= 1) return v.toStringAsFixed(4);
    return v.toStringAsFixed(4);
  }

  static List<BoxShadow> get cardShadow => const [
        BoxShadow(
          color: panelShadow,
          blurRadius: 20,
          offset: Offset(0, 10),
        ),
      ];
}
