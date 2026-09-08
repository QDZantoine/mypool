import 'json_tolerant.dart';

/// Mode de pilotage de la filtration.
enum FiltrationMode {
  /// Durée calculée depuis la température de l'eau, decoupee en créneaux.
  automatic,

  /// Créneaux saisis à la main par l'utilisateur.
  manual,

  /// Filtration permanente (canicule, après un traitement choc).
  continuous,

  /// Filtration arrêtée (hivernage).
  off,
}

/// Un créneau de filtration : une heure de depart et une durée.
///
/// Stocke en minutes depuis minuit plutôt qu'en `DateTime` : un planning est
/// une règle qui se répète chaque jour, il ne porte pas de date. C'est aussi
/// la forme attendue par le module, qui exécute le planning sans le téléphone.
class FiltrationCycle {
  const FiltrationCycle({
    required this.startMinuteOfDay,
    required this.durationMinutes,
  });

  /// Minutes depuis minuit, de 0 à 1 439.
  final int startMinuteOfDay;

  final int durationMinutes;

  /// Minute de fin, ramenée dans la journée : un créneau peut passer minuit.
  int get endMinuteOfDay =>
      (startMinuteOfDay + durationMinutes) % _minutesPerDay;

  static const int _minutesPerDay = 24 * 60;

  Duration get duration => Duration(minutes: durationMinutes);

  /// « 10:45 »
  String get formattedStart => formatMinuteOfDay(startMinuteOfDay);

  /// « 17:15 »
  String get formattedEnd => formatMinuteOfDay(endMinuteOfDay);

  /// « 6 h 30 », « 45 min »
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
      // Une heure de depart hors journée est ramenée dans la journée plutôt
      // que rejetée : le créneau reste exécutable.
      startMinuteOfDay: readInt(json, 'startMinuteOfDay', 0) % _minutesPerDay,
      // Une durée négative ou superieure à la journée est bornée.
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

/// Le planning de filtration d'une journée.
class FiltrationSchedule {
  const FiltrationSchedule({
    required this.mode,
    required this.cycles,
    this.waterTemperatureC,
    this.recommendedMinutes = 0,
    this.turnoverMinutes = 0,
  });

  /// Planning vide : filtration arrêtée, aucun créneau.
  static const FiltrationSchedule empty = FiltrationSchedule(
    mode: FiltrationMode.off,
    cycles: <FiltrationCycle>[],
  );

  final FiltrationMode mode;

  final List<FiltrationCycle> cycles;

  /// Température qui a servi au calcul, quand le mode est automatique.
  final double? waterTemperatureC;

  /// Durée totale recommandee, en minutes. La somme des créneaux doit lui être
  /// egale : c'est l'invariant du découpage.
  final int recommendedMinutes;

  /// Durée d'une rotation complète du volume d'eau, en minutes.
  final int turnoverMinutes;

  /// Somme réelle des créneaux, en minutes.
  int get totalMinutes => cycles.fold<int>(
    0,
    (int sum, FiltrationCycle cycle) => sum + cycle.durationMinutes,
  );

  Duration get total => Duration(minutes: totalMinutes);

  Duration get recommended => Duration(minutes: recommendedMinutes);

  Duration get turnover => Duration(minutes: turnoverMinutes);

  /// Nombre de rotations du volume assurees par le planning.
  ///
  /// En dessous de 1 le bassin n'a pas vu passer toute son eau dans le filtre.
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
