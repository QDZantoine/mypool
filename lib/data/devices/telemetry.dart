import '../../models/json_tolerant.dart';

enum TelemetryMotion { idle, opening, closing }

class PoolTelemetry {
  const PoolTelemetry({
    required this.receivedAt,
    this.deviceId = '',
    this.ph,
    this.phRaw,
    this.temperatureC,
    this.coverPosition,
    this.coverMotion = TelemetryMotion.idle,
    this.coverEstimated = true,
    this.pumpOn,
    this.pumpRunMinutes,
    this.heaterOn,
    this.heaterAuto,
    this.heaterSetpointC,
    this.filterAlert = false,
    this.uptimeSeconds,
  });

  final DateTime receivedAt;

  final String deviceId;

  final double? ph;

  final int? phRaw;

  final double? temperatureC;

  final double? coverPosition;

  final TelemetryMotion coverMotion;

  final bool coverEstimated;

  final bool? pumpOn;
  final int? pumpRunMinutes;
  final bool? heaterOn;
  final bool? heaterAuto;
  final double? heaterSetpointC;

  final bool filterAlert;

  final int? uptimeSeconds;

  bool get hasNoMeasurement => ph == null && temperatureC == null;

  PoolTelemetry copyWith({
    DateTime? receivedAt,
    String? deviceId,
    double? ph,
    int? phRaw,
    double? temperatureC,
    double? coverPosition,
    TelemetryMotion? coverMotion,
    bool? coverEstimated,
    bool? pumpOn,
    int? pumpRunMinutes,
    bool? heaterOn,
    bool? heaterAuto,
    double? heaterSetpointC,
    bool? filterAlert,
    int? uptimeSeconds,
  }) {
    return PoolTelemetry(
      receivedAt: receivedAt ?? this.receivedAt,
      deviceId: deviceId ?? this.deviceId,
      ph: ph ?? this.ph,
      phRaw: phRaw ?? this.phRaw,
      temperatureC: temperatureC ?? this.temperatureC,
      coverPosition: coverPosition ?? this.coverPosition,
      coverMotion: coverMotion ?? this.coverMotion,
      coverEstimated: coverEstimated ?? this.coverEstimated,
      pumpOn: pumpOn ?? this.pumpOn,
      pumpRunMinutes: pumpRunMinutes ?? this.pumpRunMinutes,
      heaterOn: heaterOn ?? this.heaterOn,
      heaterAuto: heaterAuto ?? this.heaterAuto,
      heaterSetpointC: heaterSetpointC ?? this.heaterSetpointC,
      filterAlert: filterAlert ?? this.filterAlert,
      uptimeSeconds: uptimeSeconds ?? this.uptimeSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'deviceId': deviceId,
      'ph': ph,
      'phRaw': phRaw,
      'tempC': temperatureC,
      'cover': <String, dynamic>{
        'position': coverPosition,
        'motion': coverMotion.name,
        'estimated': coverEstimated,
      },
      'pump': <String, dynamic>{'on': pumpOn, 'runMinutes': pumpRunMinutes},
      'heater': <String, dynamic>{
        'on': heaterOn,
        'auto': heaterAuto,
        'setpointC': heaterSetpointC,
      },
      'filterAlert': filterAlert,
      'uptimeS': uptimeSeconds,
    };
  }

  factory PoolTelemetry.fromJson(Object? raw, {required DateTime receivedAt}) {
    final Map<String, dynamic> json = asJsonMap(raw);
    final Map<String, dynamic> cover = asJsonMap(json['cover']);
    final Map<String, dynamic> pump = asJsonMap(json['pump']);
    final Map<String, dynamic> heater = asJsonMap(json['heater']);

    return PoolTelemetry(
      receivedAt: receivedAt,
      deviceId: readString(json, 'deviceId', ''),

      ph: _bounded(readNullableDouble(json, 'ph'), 0.0, 14.0),
      phRaw: readNullableDouble(json, 'phRaw')?.round(),
      temperatureC: _bounded(readNullableDouble(json, 'tempC'), -50.0, 100.0),
      coverPosition: _bounded(readNullableDouble(cover, 'position'), 0.0, 1.0),
      coverMotion: readEnum(
        cover,
        'motion',
        TelemetryMotion.values,
        TelemetryMotion.idle,
      ),
      coverEstimated: readBool(cover, 'estimated', true),
      pumpOn: _nullableBool(pump, 'on'),
      pumpRunMinutes: readNullableDouble(pump, 'runMinutes')?.round(),
      heaterOn: _nullableBool(heater, 'on'),
      heaterAuto: _nullableBool(heater, 'auto'),
      heaterSetpointC: _bounded(
        readNullableDouble(heater, 'setpointC'),
        0.0,
        50.0,
      ),
      filterAlert: readBool(json, 'filterAlert', false),
      uptimeSeconds: readNullableDouble(json, 'uptimeS')?.round(),
    );
  }

  static double? _bounded(double? value, double min, double max) {
    if (value == null || value < min || value > max) {
      return null;
    }
    return value;
  }

  static bool? _nullableBool(Map<String, dynamic> json, String key) {
    final Object? raw = json[key];
    if (raw == null) {
      return null;
    }
    if (raw is bool) {
      return raw;
    }
    if (raw is num) {
      return raw != 0;
    }
    if (raw is String) {
      final String lower = raw.toLowerCase();
      if (lower == 'true' || lower == '1') {
        return true;
      }
      if (lower == 'false' || lower == '0') {
        return false;
      }
    }
    return null;
  }

  @override
  String toString() =>
      'PoolTelemetry(pH $ph, $temperatureC °C, '
      'bâche ${coverMotion.name})';
}
