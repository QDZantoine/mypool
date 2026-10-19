import 'json_tolerant.dart';

enum ParameterStatus {

  unknown,

  veryLow,

  low,

  ideal,

  high,

  veryHigh,
}

enum WaterParameter {

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

  final double target;

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

  String formatValue(double value) {
    final String text = value.toStringAsFixed(decimals);
    final String withComma = text.replaceAll('.', ',');
    return unit.isEmpty ? withComma : '$withComma $unit';
  }
}

enum MeasurementSource {

  manual,

  sensor,
}

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

  final MeasurementSource source;

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
