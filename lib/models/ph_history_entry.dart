import 'json_tolerant.dart';

/// Modèle d'entrée d'historique de mesure de pH.
class PhHistoryEntry {
  const PhHistoryEntry({
    required this.timestamp,
    required this.ph,
  });

  /// Date et heure du relevé.
  final DateTime timestamp;

  /// Valeur mesurée du pH (ex: 7.2).
  final double ph;

  /// Lecture tolérante depuis un objet JSON (supporte InfluxDB _value/_time).
  factory PhHistoryEntry.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> map = asJsonMap(json);

    final double phValue = readNullableDouble(map, 'ph') ??
        readNullableDouble(map, '_value') ??
        readNullableDouble(map, 'value') ??
        7.2;

    final DateTime dt = readNullableDateTime(map, 'timestamp') ??
        readNullableDateTime(map, '_time') ??
        readNullableDateTime(map, 'time') ??
        DateTime.now();

    return PhHistoryEntry(
      timestamp: dt,
      ph: phValue,
    );
  }

  /// Export vers JSON.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'timestamp': timestamp.toIso8601String(),
      'ph': ph,
    };
  }

  /// Copie modifiable immuable.
  PhHistoryEntry copyWith({
    DateTime? timestamp,
    double? ph,
  }) {
    return PhHistoryEntry(
      timestamp: timestamp ?? this.timestamp,
      ph: ph ?? this.ph,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PhHistoryEntry &&
        other.timestamp == timestamp &&
        other.ph == ph;
  }

  @override
  int get hashCode => Object.hash(timestamp, ph);

  @override
  String toString() => 'PhHistoryEntry(timestamp: $timestamp, ph: $ph)';
}
