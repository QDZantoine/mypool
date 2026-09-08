import 'json_tolerant.dart';

/// État d'un paramètre par rapport à sa plage de référence.
enum ParameterStatus {
  /// Aucune mesure saisie : rien à conclure, et surtout rien à doser.
  unknown,

  /// Sous la plage acceptable : correction prioritaire.
  veryLow,

  /// Entre la plage acceptable et la plage idéale, cote bas.
  low,

  /// Dans la plage idéale.
  ideal,

  /// Entre la plage idéale et la plage acceptable, cote haut.
  high,

  /// Au-delà de la plage acceptable : correction prioritaire.
  veryHigh,
}

/// Paramètres mesures et leurs plages de référence (annexe À.1).
///
/// La plage « idéale » est celle à viser ; la plage « acceptable » est celle
/// au-delà de laquelle la correction devient prioritaire. Les deux existent
/// parce qu'un pH de 7,5 n'est pas un problème, alors qu'un pH de 8,2 en est un.
enum WaterParameter {
  /// Le pH commande l'efficacite du chlore : à 7,2 environ 60 % du chlore est
  /// actif, à 8,0 il n'en reste qu'un quart.
  ph(
    label: 'pH',
    unit: '',
    idealMin: 7.0,
    idealMax: 7.4,
    acceptableMin: 6.8,
    acceptableMax: 7.6,
    target: 7.2,
    decimals: 1,
  ),

  /// Chlore libre : le désinfectant réellement disponible.
  freeChlorine(
    label: 'Chlore libre',
    unit: 'mg/L',
    idealMin: 1.0,
    idealMax: 2.0,
    acceptableMin: 0.5,
    acceptableMax: 3.0,
    target: 1.5,
    decimals: 1,
  ),

  /// Chlore combiné (chloramines) : du chlore déjà consommé, irritant et
  /// inefficace. Au-delà de 0,6 mg/L un traitement choc est nécessaire.
  combinedChlorine(
    label: 'Chlore combiné',
    unit: 'mg/L',
    idealMin: 0.0,
    idealMax: 0.2,
    acceptableMin: 0.0,
    acceptableMax: 0.6,
    target: 0.0,
    decimals: 1,
  ),

  /// TAC (alcalinité totale) : le tampon qui empeche le pH de varier. On le
  /// corrige avant le pH, sinon le pH repart.
  tac(
    label: 'TAC',
    unit: 'mg/L',
    idealMin: 80.0,
    idealMax: 120.0,
    acceptableMin: 60.0,
    acceptableMax: 180.0,
    target: 100.0,
    decimals: 0,
  ),

  /// TH (durete calcique) : trop bas l'eau attaque les joints et le liner,
  /// trop haut elle entartre.
  th(
    label: 'TH',
    unit: 'mg/L',
    idealMin: 100.0,
    idealMax: 300.0,
    acceptableMin: 80.0,
    acceptableMax: 400.0,
    target: 200.0,
    decimals: 0,
  ),

  /// Stabilisant (acide cyanurique) : protège le chlore des UV mais le freine.
  /// Il ne s'elimine pas : au-delà de 75 mg/L, seul le renouvellement d'eau
  /// fait baisser la valeur.
  stabilizer(
    label: 'Stabilisant',
    unit: 'mg/L',
    idealMin: 20.0,
    idealMax: 50.0,
    acceptableMin: 10.0,
    acceptableMax: 75.0,
    target: 30.0,
    decimals: 0,
  ),

  /// Sel : uniquement pour les bassins à électrolyse.
  salt(
    label: 'Sel',
    unit: 'g/L',
    idealMin: 3.0,
    idealMax: 5.0,
    acceptableMin: 2.5,
    acceptableMax: 6.0,
    target: 4.0,
    decimals: 1,
  ),

  /// Température : elle ne se corrige pas, mais elle commande la durée de
  /// filtration et la consommation de chlore.
  temperature(
    label: 'Température',
    unit: '°C',
    idealMin: 24.0,
    idealMax: 28.0,
    acceptableMin: 10.0,
    acceptableMax: 32.0,
    target: 26.0,
    decimals: 1,
  );

  const WaterParameter({
    required this.label,
    required this.unit,
    required this.idealMin,
    required this.idealMax,
    required this.acceptableMin,
    required this.acceptableMax,
    required this.target,
    required this.decimals,
  });

  final String label;
  final String unit;
  final double idealMin;
  final double idealMax;
  final double acceptableMin;
  final double acceptableMax;

  /// Valeur visee par une correction. Ce n'est pas le milieu de la plage
  /// idéale : pour le pH on vise 7,2 parce que c'est le meilleur compromis
  /// entre efficacité du chlore et confort des yeux.
  final double target;

  /// Nombre de décimales à l'affichage.
  final int decimals;

  ParameterStatus statusOf(double? value) {
    if (value == null) {
      return ParameterStatus.unknown;
    }
    if (value < acceptableMin) {
      return ParameterStatus.veryLow;
    }
    if (value < idealMin) {
      return ParameterStatus.low;
    }
    if (value > acceptableMax) {
      return ParameterStatus.veryHigh;
    }
    if (value > idealMax) {
      return ParameterStatus.high;
    }
    return ParameterStatus.ideal;
  }

  /// Formate une valeur pour l'affichage, avec virgule décimale.
  String formatValue(double value) {
    final String text = value.toStringAsFixed(decimals);
    final String withComma = text.replaceAll('.', ',');
    return unit.isEmpty ? withComma : '$withComma $unit';
  }
}

/// Origine d'une mesure.
///
/// Une bandelette et une sonde non calibrée ne se valent pas : l'historique
/// doit permettre de les distinguer (addendum § 5). La distinction prépare
/// aussi l'arrivée d'une vraie sonde de température.
enum MeasurementSource {
  /// Saisie par l'utilisateur : bandelette, pastille, testeur électronique.
  manual,

  /// Remontée automatiquement par une sonde du module.
  sensor,
}

/// Une série de mesures prise à un instant donné.
///
/// Tous les paramètres sont optionnels : on saisit ce qu'on à mesure. Une
/// valeur absente n'est jamais interpretee comme un zéro, sinon un pH non
/// mesure declencherait une correction massive.
class WaterReading {
  const WaterReading({
    required this.takenAt,
    this.ph,
    this.freeChlorine,
    this.combinedChlorine,
    this.tac,
    this.th,
    this.stabilizer,
    this.salt,
    this.temperature,
    this.note,
    this.source = MeasurementSource.manual,
  });

  final DateTime takenAt;
  final double? ph;
  final double? freeChlorine;
  final double? combinedChlorine;
  final double? tac;
  final double? th;
  final double? stabilizer;
  final double? salt;
  final double? temperature;
  final String? note;

  /// Origine de la mesure. Par défaut une saisie : une mesure dont on ne sait
  /// rien vient de l'utilisateur, pas d'une sonde.
  final MeasurementSource source;

  /// Aucune valeur saisie : le moteur ne doit produire aucune recommandation.
  bool get isEmpty =>
      ph == null &&
      freeChlorine == null &&
      combinedChlorine == null &&
      tac == null &&
      th == null &&
      stabilizer == null &&
      salt == null &&
      temperature == null;

  bool get isNotEmpty => !isEmpty;

  double? valueOf(WaterParameter parameter) {
    switch (parameter) {
      case WaterParameter.ph:
        return ph;
      case WaterParameter.freeChlorine:
        return freeChlorine;
      case WaterParameter.combinedChlorine:
        return combinedChlorine;
      case WaterParameter.tac:
        return tac;
      case WaterParameter.th:
        return th;
      case WaterParameter.stabilizer:
        return stabilizer;
      case WaterParameter.salt:
        return salt;
      case WaterParameter.temperature:
        return temperature;
    }
  }

  ParameterStatus statusOf(WaterParameter parameter) {
    return parameter.statusOf(valueOf(parameter));
  }

  WaterReading copyWith({
    DateTime? takenAt,
    double? ph,
    double? freeChlorine,
    double? combinedChlorine,
    double? tac,
    double? th,
    double? stabilizer,
    double? salt,
    double? temperature,
    String? note,
    MeasurementSource? source,
  }) {
    return WaterReading(
      takenAt: takenAt ?? this.takenAt,
      ph: ph ?? this.ph,
      freeChlorine: freeChlorine ?? this.freeChlorine,
      combinedChlorine: combinedChlorine ?? this.combinedChlorine,
      tac: tac ?? this.tac,
      th: th ?? this.th,
      stabilizer: stabilizer ?? this.stabilizer,
      salt: salt ?? this.salt,
      temperature: temperature ?? this.temperature,
      note: note ?? this.note,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'takenAt': takenAt.toIso8601String(),
      'ph': ph,
      'freeChlorine': freeChlorine,
      'combinedChlorine': combinedChlorine,
      'tac': tac,
      'th': th,
      'stabilizer': stabilizer,
      'salt': salt,
      'temperature': temperature,
      'note': note,
      'source': source.name,
    };
  }

  /// Reconstruit une mesure. Une date illisible retombe sur l'epoque Unix
  /// plutôt que sur l'heure courante : le domaine ne lit jamais l'horloge, et
  /// une date fausse mais stable reste comparable d'un lancement à l'autre.
  factory WaterReading.fromJson(Object? raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return WaterReading(
      takenAt: readDateTime(
        json,
        'takenAt',
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
      ph: readNullableDouble(json, 'ph'),
      freeChlorine: readNullableDouble(json, 'freeChlorine'),
      combinedChlorine: readNullableDouble(json, 'combinedChlorine'),
      tac: readNullableDouble(json, 'tac'),
      th: readNullableDouble(json, 'th'),
      stabilizer: readNullableDouble(json, 'stabilizer'),
      salt: readNullableDouble(json, 'salt'),
      temperature: readNullableDouble(json, 'temperature'),
      note: readNullableString(json, 'note'),
      // Une origine illisible vaut « saisie » : on ne prête pas à une mesure
      // la crédibilité d'une sonde sans preuve.
      source: readEnum(
        json,
        'source',
        MeasurementSource.values,
        MeasurementSource.manual,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WaterReading &&
        other.takenAt == takenAt &&
        other.ph == ph &&
        other.freeChlorine == freeChlorine &&
        other.combinedChlorine == combinedChlorine &&
        other.tac == tac &&
        other.th == th &&
        other.stabilizer == stabilizer &&
        other.salt == salt &&
        other.temperature == temperature &&
        other.note == note &&
        other.source == source;
  }

  @override
  int get hashCode => Object.hash(
    takenAt,
    ph,
    freeChlorine,
    combinedChlorine,
    tac,
    th,
    stabilizer,
    salt,
    temperature,
    note,
  );

  @override
  String toString() => 'WaterReading($takenAt, pH $ph, Cl $freeChlorine)';
}
