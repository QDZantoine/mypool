import 'dart:math' as math;

import '../models/water_reading.dart';

enum WaterBalanceVerdict {

  corrosive,

  balanced,

  scaling,

  unknown,
}

class WaterBalanceResult {
  const WaterBalanceResult({
    required this.index,
    required this.verdict,
    required this.temperatureFactor,
    required this.calciumFactor,
    required this.alkalinityFactor,
  });

  final double index;

  final WaterBalanceVerdict verdict;

  final double temperatureFactor;
  final double calciumFactor;
  final double alkalinityFactor;

  String get formattedIndex =>
      index.toStringAsFixed(2).replaceAll('.', ',').replaceAll('-', '−');

  @override
  String toString() =>
      'WaterBalanceResult(${index.toStringAsFixed(2)}, ${verdict.name})';
}

class WaterBalance {

  static const double solubilityConstant = 12.1;

  static const double balancedTolerance = 0.3;

  static const List<double> _temperatureBreakpointsC = <double>[
    0.0,
    3.0,
    8.0,
    12.0,
    16.0,
    19.0,
    24.0,
    29.0,
    34.0,
    41.0,
    53.0,
  ];

  static const List<double> _temperatureFactors = <double>[
    0.0,
    0.1,
    0.2,
    0.3,
    0.4,
    0.5,
    0.6,
    0.7,
    0.8,
    0.9,
    1.0,
  ];

  static double temperatureFactor(double temperatureC) {
    if (temperatureC <= _temperatureBreakpointsC.first) {
      return _temperatureFactors.first;
    }
    if (temperatureC >= _temperatureBreakpointsC.last) {
      return _temperatureFactors.last;
    }

    int index = 0;
    while (temperatureC > _temperatureBreakpointsC[index + 1]) {
      index++;
    }
    final double low = _temperatureBreakpointsC[index];
    final double high = _temperatureBreakpointsC[index + 1];
    final double ratio = (temperatureC - low) / (high - low);
    return _temperatureFactors[index] +
        ratio * (_temperatureFactors[index + 1] - _temperatureFactors[index]);
  }

  static double calciumFactor(double thMgL) {
    return _log10(thMgL) - 0.4;
  }

  static double alkalinityFactor(double tacMgL) {
    return _log10(tacMgL);
  }

  static double? langelierIndex({
    required double ph,
    required double tacMgL,
    required double thMgL,
    required double temperatureC,
  }) {
    if (tacMgL <= 0 || thMgL <= 0) {
      return null;
    }
    return ph +
        temperatureFactor(temperatureC) +
        calciumFactor(thMgL) +
        alkalinityFactor(tacMgL) -
        solubilityConstant;
  }

  static WaterBalanceVerdict verdictFor(double? index) {
    if (index == null) {
      return WaterBalanceVerdict.unknown;
    }
    if (index < -balancedTolerance) {
      return WaterBalanceVerdict.corrosive;
    }
    if (index > balancedTolerance) {
      return WaterBalanceVerdict.scaling;
    }
    return WaterBalanceVerdict.balanced;
  }

  static WaterBalanceResult? evaluate({
    required double ph,
    required double tacMgL,
    required double thMgL,
    required double temperatureC,
  }) {
    final double? index = langelierIndex(
      ph: ph,
      tacMgL: tacMgL,
      thMgL: thMgL,
      temperatureC: temperatureC,
    );
    if (index == null) {
      return null;
    }
    return WaterBalanceResult(
      index: index,
      verdict: verdictFor(index),
      temperatureFactor: temperatureFactor(temperatureC),
      calciumFactor: calciumFactor(thMgL),
      alkalinityFactor: alkalinityFactor(tacMgL),
    );
  }

  static WaterBalanceResult? fromReading(WaterReading reading) {
    final double? ph = reading.ph;
    final double? tac = reading.tac;
    final double? th = reading.th;
    final double? temperature = reading.temperature;
    if (ph == null || tac == null || th == null || temperature == null) {
      return null;
    }
    return evaluate(ph: ph, tacMgL: tac, thMgL: th, temperatureC: temperature);
  }

  static String explain(WaterBalanceVerdict verdict) {
    switch (verdict) {
      case WaterBalanceVerdict.corrosive:
        return 'L’eau est agressive : il lui manque du calcaire, elle va le '
            'chercher dans les joints, le béton et les pièces à sceller. On '
            'corrige en remontant le TH, puis le TAC.';
      case WaterBalanceVerdict.balanced:
        return 'L’eau est équilibrée : elle ne dépose pas de calcaire et '
            'n’attaque pas le revêtement. Rien à faire de ce côté.';
      case WaterBalanceVerdict.scaling:
        return 'L’eau est entartrante : le calcaire se dépose sur les parois, '
            'dans le filtre et sur la cellule. On corrige en baissant le pH, '
            'puis le TAC.';
      case WaterBalanceVerdict.unknown:
        return 'Il manque le pH, le TAC, le TH ou la température pour conclure '
            'sur l’équilibre de l’eau.';
    }
  }

  static double _log10(double value) => math.log(value) / math.ln10;
}
