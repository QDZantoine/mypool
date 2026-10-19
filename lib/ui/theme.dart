import 'package:flutter/material.dart';

import '../models/dose_recommendation.dart';
import '../models/water_reading.dart';

class AppTheme {

  static const Color ink = Color(0xFF05263B);

  static const Color surface = Color(0xFFEDF4F7);

  static const Color card = Color(0xFFFFFFFF);

  static const Color surfaceDark = Color(0xFF04141F);
  static const Color cardDark = Color(0xFF0A2231);
  static const Color inkDark = Color(0xFFE6F1F6);

  static const Color _chlorineLight = Color(0xFF0C7C7C);
  static const Color _chlorineDark = Color(0xFF0E9796);

  static const Color _inRangeLight = Color(0xFF297D56);
  static const Color _inRangeDark = Color(0xFF319868);

  static const Color _driftLight = Color(0xFF9E6115);
  static const Color _driftDark = Color(0xFFE08A1E);

  static const Color _acidLight = Color(0xFFCD334D);
  static const Color _acidDark = Color(0xFFD85F74);

  static const Color _unmeasuredLight = Color(0xFF567382);
  static const Color _unmeasuredDark = Color(0xFF8FA8B5);

  static const Color _inkMutedLight = Color(0xFF587383);
  static const Color _inkMutedDark = Color(0xFF93AEBC);

  static Brightness _brightness = Brightness.light;

  static void applyBrightness(Brightness brightness) {
    _brightness = brightness;
  }

  static bool get _isDark => _brightness == Brightness.dark;

  static Color get chlorine => _isDark ? _chlorineDark : _chlorineLight;
  static Color get inRange => _isDark ? _inRangeDark : _inRangeLight;
  static Color get drift => _isDark ? _driftDark : _driftLight;
  static Color get acid => _isDark ? _acidDark : _acidLight;
  static Color get unmeasured => _isDark ? _unmeasuredDark : _unmeasuredLight;
  static Color get inkMuted => _isDark ? _inkMutedDark : _inkMutedLight;

  static const double touchTarget = 56.0;

  static const double gap = 4.0;
  static const double gutter = 20.0;
  static const double radius = 18.0;

  static const Duration motion = Duration(milliseconds: 280);

  static const List<FontFeature> _tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  static TextStyle reading(double size) => TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w300,
    letterSpacing: -size * 0.03,
    height: 0.95,
    fontFeatures: _tabular,
  );

  static const TextStyle eyebrow = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.3,
    height: 1.2,
  );

  static ThemeData light() {
    applyBrightness(Brightness.light);
    return _build(
      brightness: Brightness.light,
      background: surface,
      cardColor: card,
      onSurface: ink,
      onSurfaceMuted: _inkMutedLight,
    );
  }

  static ThemeData dark() {
    applyBrightness(Brightness.dark);
    return _build(
      brightness: Brightness.dark,
      background: surfaceDark,
      cardColor: cardDark,
      onSurface: inkDark,
      onSurfaceMuted: _inkMutedDark,
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color cardColor,
    required Color onSurface,
    required Color onSurfaceMuted,
  }) {
    final ColorScheme scheme =
        ColorScheme.fromSeed(
          seedColor: chlorine,
          brightness: brightness,
        ).copyWith(
          surface: background,
          onSurface: onSurface,
          surfaceContainerLowest: cardColor,
          outline: onSurfaceMuted,
          primary: chlorine,
          error: acid,
        );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      textTheme: TextTheme(

        displayLarge: reading(76),
        displayMedium: reading(52),
        displaySmall: reading(34),

        headlineMedium: TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.15,
          color: onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),

        bodyLarge: TextStyle(fontSize: 17, height: 1.5, color: onSurface),
        bodyMedium: TextStyle(
          fontSize: 16,
          height: 1.45,
          color: onSurfaceMuted,
        ),
        labelLarge: eyebrow.copyWith(color: onSurfaceMuted),
        labelMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: onSurfaceMuted,
          fontFeatures: _tabular,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: onSurface,
        ),
        iconTheme: IconThemeData(color: onSurface),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        surfaceTintColor: Colors.transparent,

        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(touchTarget),
          backgroundColor: chlorine,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(touchTarget),
          foregroundColor: onSurface,
          side: BorderSide(color: onSurfaceMuted.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: chlorine,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: onSurfaceMuted.withValues(alpha: 0.18),
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 14,
        contentPadding: EdgeInsets.symmetric(horizontal: gutter, vertical: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: chlorine.withValues(alpha: 0.16),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 12.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? chlorine
                : onSurfaceMuted,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: onSurfaceMuted.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: onSurfaceMuted.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: chlorine, width: 2),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: eyebrow.copyWith(color: onSurfaceMuted),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cardColor,
        selectedColor: chlorine,
        side: BorderSide(color: onSurfaceMuted.withValues(alpha: 0.25)),
        labelStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        shape: const StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: const TextStyle(fontSize: 16, color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static List<Color> scaleFor(WaterParameter parameter) {
    switch (parameter) {
      case WaterParameter.ph:

        return const <Color>[
          Color(0xFFF2D849),
          Color(0xFFF0A63C),
          Color(0xFFE4653F),
          Color(0xFFC0325A),
        ];
      case WaterParameter.freeChlorine:

        return const <Color>[
          Color(0xFFF3F1E8),
          Color(0xFFF0A8C0),
          Color(0xFFC13B7A),
        ];
      case WaterParameter.combinedChlorine:
        return const <Color>[Color(0xFFF3F1E8), Color(0xFFB07AA8)];
      case WaterParameter.tac:

        return const <Color>[
          Color(0xFFE8E4A8),
          Color(0xFF7FB069),
          Color(0xFF2D6A4F),
        ];
      case WaterParameter.th:

        return const <Color>[
          Color(0xFFE8C9A0),
          Color(0xFFB07A4A),
          Color(0xFF6B4478),
        ];
      case WaterParameter.stabilizer:

        return const <Color>[
          Color(0xFFEDF4F7),
          Color(0xFF9DB4C0),
          Color(0xFF4A5C68),
        ];
      case WaterParameter.salt:
        return const <Color>[Color(0xFFEDF4F7), Color(0xFF4A90C2)];
      case WaterParameter.temperature:

        return const <Color>[
          Color(0xFF4A90C2),
          Color(0xFF7FB069),
          Color(0xFFE08A1E),
          Color(0xFFD1435B),
        ];
    }
  }

  static Color colorForStatus(ParameterStatus status) {
    switch (status) {
      case ParameterStatus.ideal:
        return inRange;
      case ParameterStatus.low:
      case ParameterStatus.high:
        return drift;
      case ParameterStatus.veryLow:
      case ParameterStatus.veryHigh:
        return acid;
      case ParameterStatus.unknown:
        return unmeasured;
    }
  }

  static String labelForStatus(ParameterStatus status) {
    switch (status) {
      case ParameterStatus.ideal:
        return 'dans la plage';
      case ParameterStatus.low:
        return 'un peu bas';
      case ParameterStatus.high:
        return 'un peu haut';
      case ParameterStatus.veryLow:
        return 'trop bas';
      case ParameterStatus.veryHigh:
        return 'trop haut';
      case ParameterStatus.unknown:
        return 'non mesuré';
    }
  }

  static Color colorForPriority(ActionPriority priority) {
    switch (priority) {
      case ActionPriority.urgent:
        return acid;
      case ActionPriority.alkalinity:
      case ActionPriority.ph:
      case ActionPriority.chlorine:
        return drift;
      case ActionPriority.balance:
      case ActionPriority.information:
        return chlorine;
    }
  }
}
