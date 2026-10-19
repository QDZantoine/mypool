import 'json_tolerant.dart';

enum FiltrationMode {

  automatic,

  manual,

  continuous,

  off,
}

class FiltrationCycle {
  const FiltrationCycle({
    required this.startMinuteOfDay,
    required this.durationMinutes,
  });

  final int startMinuteOfDay;

  final int durationMinutes;

  int get endMinuteOfDay =>
      (startMinuteOfDay + durationMinutes) % _minutesPerDay;

  static const int _minutesPerDay = 24 * 60;

  Duration get duration => Duration(minutes: durationMinutes);

  String get formattedStart => formatMinuteOfDay(startMinuteOfDay);

  String get formattedEnd => formatMinuteOfDay(endMinuteOfDay);

  String get formattedDuration => formatDuration(durationMinutes);

  static String formatMinuteOfDay(int minuteOfDay) {
    final int normalised = minuteOfDay % _minutesPerDay;
    final int hours = normalised ~/ 60;
    final int minutes = normalised % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  static String formatDuration(int totalMinutes) {
    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes % 60;
    if (hours == 0) {
      return '$minutes min';
    }
    if (minutes == 0) {
      return '$hours h';
    }
    return '$hours h ${minutes.toString().padLeft(2, '0')}';
  }

  FiltrationCycle copyWith({int? startMinuteOfDay, int? durationMinutes}) {
    return FiltrationCycle(
      startMinuteOfDay: startMinuteOfDay ?? this.startMinuteOfDay,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'startMinuteOfDay': startMinuteOfDay,
      'durationMinutes': durationMinutes,
    };
  }

  factory FiltrationCycle.fromJson(Object? raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return FiltrationCycle(

      startMinuteOfDay: readInt(json, 'startMinuteOfDay', 0) % _minutesPerDay,

      durationMinutes: readInt(
        json,
        'durationMinutes',
        0,
      ).clamp(0, _minutesPerDay),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FiltrationCycle &&
        other.startMinuteOfDay == startMinuteOfDay &&
        other.durationMinutes == durationMinutes;
  }

  @override
  int get hashCode => Object.hash(startMinuteOfDay, durationMinutes);

  @override
  String toString() => 'FiltrationCycle($formattedStart -> $formattedEnd)';
}

class FiltrationSchedule {
  const FiltrationSchedule({
    required this.mode,
    required this.cycles,
    this.waterTemperatureC,
    this.recommendedMinutes = 0,
    this.turnoverMinutes = 0,
  });

  static const FiltrationSchedule empty = FiltrationSchedule(
    mode: FiltrationMode.off,
    cycles: <FiltrationCycle>[],
  );

  final FiltrationMode mode;

  final List<FiltrationCycle> cycles;

  final double? waterTemperatureC;

  final int recommendedMinutes;

  final int turnoverMinutes;

  int get totalMinutes => cycles.fold<int>(
    0,
    (int sum, FiltrationCycle cycle) => sum + cycle.durationMinutes,
  );

  Duration get total => Duration(minutes: totalMinutes);

  Duration get recommended => Duration(minutes: recommendedMinutes);

  Duration get turnover => Duration(minutes: turnoverMinutes);

  double get turnoverCount =>
      turnoverMinutes <= 0 ? 0.0 : totalMinutes / turnoverMinutes;

  String get formattedTotal => FiltrationCycle.formatDuration(totalMinutes);

  String get formattedTurnover =>
      FiltrationCycle.formatDuration(turnoverMinutes);

  FiltrationSchedule copyWith({
    FiltrationMode? mode,
    List<FiltrationCycle>? cycles,
    double? waterTemperatureC,
    int? recommendedMinutes,
    int? turnoverMinutes,
  }) {
    return FiltrationSchedule(
      mode: mode ?? this.mode,
      cycles: cycles ?? this.cycles,
      waterTemperatureC: waterTemperatureC ?? this.waterTemperatureC,
      recommendedMinutes: recommendedMinutes ?? this.recommendedMinutes,
      turnoverMinutes: turnoverMinutes ?? this.turnoverMinutes,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'mode': mode.name,
      'cycles': cycles
          .map((FiltrationCycle cycle) => cycle.toJson())
          .toList(growable: false),
      'waterTemperatureC': waterTemperatureC,
      'recommendedMinutes': recommendedMinutes,
      'turnoverMinutes': turnoverMinutes,
    };
  }

  factory FiltrationSchedule.fromJson(Object? raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return FiltrationSchedule(
      mode: readEnum(
        json,
        'mode',
        FiltrationMode.values,
        FiltrationMode.automatic,
      ),
      cycles: readMapList(
        json,
        'cycles',
      ).map(FiltrationCycle.fromJson).toList(growable: false),
      waterTemperatureC: readNullableDouble(json, 'waterTemperatureC'),
      recommendedMinutes: readInt(json, 'recommendedMinutes', 0).clamp(0, 1440),
      turnoverMinutes: readInt(json, 'turnoverMinutes', 0).clamp(0, 1440),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! FiltrationSchedule) {
      return false;
    }
    if (other.cycles.length != cycles.length) {
      return false;
    }
    for (int i = 0; i < cycles.length; i++) {
      if (other.cycles[i] != cycles[i]) {
        return false;
      }
    }
    return other.mode == mode &&
        other.waterTemperatureC == waterTemperatureC &&
        other.recommendedMinutes == recommendedMinutes &&
        other.turnoverMinutes == turnoverMinutes;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    Object.hashAll(cycles),
    waterTemperatureC,
    recommendedMinutes,
    turnoverMinutes,
  );

  @override
  String toString() =>
      'FiltrationSchedule(${mode.name}, ${cycles.length} creneaux, '
      '$formattedTotal)';
}
