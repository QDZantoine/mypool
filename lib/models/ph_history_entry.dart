import 'json_tolerant.dart';

class PhHistoryEntry {
  const PhHistoryEntry({
    required this.timestamp,
    required this.ph,
  });

  final DateTime timestamp;

  final double ph;

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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'timestamp': timestamp.toIso8601String(),
      'ph': ph,
    };
  }

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
