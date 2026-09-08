import 'dart:math' as math;

import '../models/water_reading.dart';

/// Verdict d'équilibre calco-carbonique.
enum WaterBalanceVerdict {
  /// Indice négatif : l'eau va chercher le calcium qui lui manque dans les
  /// joints, le béton et les pieces à sceller.
  corrosive,

  /// Indice dans la plage de tolérance : l'eau ne dissout ni ne depose.
  balanced,

  /// Indice positif : le calcaire se depose sur les parois, dans le filtre et
  /// sur la cellule d'electrolyse.
  scaling,

  /// Données insuffisantes pour conclure.
  unknown,
}

/// Resultat detaille du calcul, pour pouvoir expliquer chaque terme à l'écran.
class WaterBalanceResult {
  const WaterBalanceResult({
    required this.index,
    required this.verdict,
    required this.temperatureFactor,
    required this.calciumFactor,
    required this.alkalinityFactor,
  });

  /// Indice de saturation de Langelier.
  final double index;

  final WaterBalanceVerdict verdict;

  final double temperatureFactor;
  final double calciumFactor;
  final double alkalinityFactor;

  /// « -0,06 » — deux décimales, virgule décimale.
  String get formattedIndex =>
      index.toStringAsFixed(2).replaceAll('.', ',').replaceAll('-', '−');

  @override
  String toString() =>
      'WaterBalanceResult(${index.toStringAsFixed(2)}, ${verdict.name})';
}

/// Équilibre de l'eau, indice de Langelier (annexe À.6).
///
/// PUR : aucun import Flutter, aucun accès disque ou réseau.
///
/// LSI = pH + facteur température + facteur calcium + facteur alcalinité − 12,1
///
/// Les trois facteurs traduisent chacun un effet physique : la température
/// déplace l'équilibre du carbonate de calcium, le calcium apporte l'un des
/// deux ions, l'alcalinité apporte l'autre. La constante 12,1 est le produit de
/// solubilité du carbonate de calcium exprimé dans ces unités.
class WaterBalance {
  /// Constante de solubilité du carbonate de calcium, dans les unités de la
  /// formule (mg/L de CaCO3 pour le calcium et l'alcalinité).
  static const double solubilityConstant = 12.1;

  /// Demi-largeur de la plage d'équilibre.
  ///
  /// Entre −0,3 et +0,3 les effets sont trop faibles pour être visibles à
  /// l'échelle d'une saison : c'est la tolérance admise en piscine.
  static const double balancedTolerance = 0.3;

  /// Facteur de température, table de référence (annexe À.6).
  ///
  /// Clés en °C, valeurs sans unité. La table est celle des abaques de
  /// laboratoire ; l'interpolation lineaire entre deux points suffit, l'ecart à
  /// la courbe réelle reste sous 0,01.
  ///
  /// Cas de vérification : 26 °C tombe entre 24 °C (0,6) et 29 °C (0,7),
  /// soit 0,6 + (26 − 24) / (29 − 24) x 0,1 = 0,64.
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

  /// Facteur de température interpole.
  ///
  /// En dehors de la table, on borne au facteur extrême : une eau à −5 °C est
  /// gelee et une eau à 60 °C n'est pas une piscine, extrapoler n'aurait pas de
  /// sens physique.
  static double temperatureFactor(double temperatureC) {
    if (temperatureC <= _temperatureBreakpointsC.first) {
      return _temperatureFactors.first;
    }
    if (temperatureC >= _temperatureBreakpointsC.last) {
      return _temperatureFactors.last;
    }
    // Les deux gardes ci-dessus assurent que la température est strictement
    // entre le premier et le dernier point : l'intervalle existe forcement,
    // il n'y a pas de cas de repli à prevoir.
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

  /// Facteur calcium = log10(TH) − 0,4.
  ///
  /// Le TH est exprimé en mg/L de CaCO3 ; le −0,4 convertit vers la
  /// concentration en ion calcium seul.
  static double calciumFactor(double thMgL) {
    return _log10(thMgL) - 0.4;
  }

  /// Facteur alcalinité = log10(TAC), le TAC etant en mg/L de CaCO3.
  static double alkalinityFactor(double tacMgL) {
    return _log10(tacMgL);
  }

  /// Indice de Langelier, ou `null` si les données ne permettent pas de
  /// conclure.
  ///
  /// Un TAC ou un TH nul ou négatif rend le logarithme indéfini : on retourne
  /// `null` plutôt qu'un `-Infinity` qui se propagerait dans l'affichage.
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

  /// Calcul complet à partir de valeurs explicites.
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

  /// Calcul à partir d'une mesure. Retourne `null` des qu'une des quatre
  /// valeurs nécessaires manque : mieux vaut ne rien afficher qu'un indice
  /// calcule sur des valeurs supposees.
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

  /// Texte explicatif du verdict, affichable tel quel.
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
