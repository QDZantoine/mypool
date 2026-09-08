import '../models/filtration_schedule.dart';
import '../models/pool_config.dart';

/// Une fenêtre de la journée dans laquelle un créneau peut être place.
///
/// Les fenêtres sont disjointes : c'est ce qui garantit qu'aucun créneau ne
/// chevauche un autre, sans avoir à comparer les créneaux entre eux.
class _Window {
  const _Window({required this.centerMinute, required this.widthMinutes});

  /// Minute de la journée autour de laquelle le créneau est centre.
  final int centerMinute;

  /// Largeur de la fenêtre, en minutes. Un créneau ne peut pas la dépasser.
  final int widthMinutes;
}

/// Planification de la filtration (annexe À.7).
///
/// PUR : aucun import Flutter, aucun accès disque ou réseau, aucune lecture de
/// l'horloge. Le planning est une règle journaliere, pas une suite de dates :
/// c'est le module qui l'execute, pas le téléphone.
class FiltrationPlanner {
  static const int minutesPerDay = 24 * 60;

  /// Diviseur de la règle empirique de durée (annexe À.7).
  ///
  /// Durée recommandee = température de l'eau / 2, en heures. La consommation
  /// de chlore et la vitesse de croissance des algues augmentent avec la
  /// température ; cette règle de terrain les suit de pres.
  ///
  /// Cas de vérification : 26 °C / 2 = 13 h.
  static const double temperatureDivisor = 2.0;

  /// Plancher absolu, en minutes.
  ///
  /// Même en hivernage actif, deux heures par jour évitent que l'eau stagne
  /// dans les canalisations et que le filtre se colmaté.
  static const int minimumMinutes = 120;

  /// Plafond du mode automatique, en minutes (20 h).
  ///
  /// Au-delà, la filtration se gere en mode continu : les quatre heures
  /// restantes ne se decoupent plus en créneaux utiles, et la somme des
  /// largeurs de fenêtres est justement de 20 h.
  static const int maximumAutomaticMinutes = 1200;

  /// Seuil sous lequel un seul créneau suffit, en minutes (6 h).
  ///
  /// Sous 6 h, couper la filtration en deux fait perdre plus en amorçages et
  /// en démarrages de pompe que ce que le fractionnement apporte.
  static const int singleCycleMaxMinutes = 360;

  /// Seuil sous lequel deux créneaux suffisent, en minutes (12 h).
  static const int twoCyclesMaxMinutes = 720;

  /// Repartition de la durée entre les créneaux.
  ///
  /// Le créneau de journée est toujours le plus long : c'est aux heures
  /// chaudes, sous le soleil et avec des baigneurs, que la demande en chlore
  /// est maximale et que les algues demarrent.
  static const List<double> _oneCycleShares = <double>[1.0];
  static const List<double> _twoCycleShares = <double>[0.60, 0.40];
  static const List<double> _threeCycleShares = <double>[0.50, 0.30, 0.20];

  /// Fenêtres de placement, dans l'ordre de remplissage.
  ///
  /// - journée 09:00-19:00, centree sur 14:00 : le pic de chaleur ;
  /// - nuit 23:00-07:00, centree sur 03:00 : brassage et heures creuses ;
  /// - soirée 19:00-23:00, centree sur 21:00 : reprise après la baignade.
  static const List<_Window> _windows = <_Window>[
    _Window(centerMinute: 14 * 60, widthMinutes: 600),
    _Window(centerMinute: 3 * 60, widthMinutes: 480),
    _Window(centerMinute: 21 * 60, widthMinutes: 240),
  ];

  /// Durée d'une rotation complète du volume d'eau.
  ///
  /// Rotation = volume / (débit nominal x rendement). Le rendement traduit les
  /// pertes de charge et l'encrassement : une pompe de 10 m3/h à 75 % ne fait
  /// réellement passer que 7,5 m3/h.
  ///
  /// Cas de vérification : 40 m3 / (10 x 0,75) = 5,333 h = 320 min = 5 h 20.
  static Duration turnoverTime({
    required double volumeM3,
    required double flowM3PerHour,
    required double efficiency,
  }) {
    final double effectiveFlow = flowM3PerHour * efficiency;
    if (volumeM3 <= 0 || effectiveFlow <= 0) {
      return Duration.zero;
    }
    final double hours = volumeM3 / effectiveFlow;
    return Duration(minutes: (hours * 60).round());
  }

  /// Durée de filtration recommandee pour une journée.
  ///
  /// Règle température / 2, avec deux garde-fous :
  /// - au moins une rotation complète, sinon toute l'eau n'a pas vu le filtre ;
  /// - au moins deux heures, et au plus vingt.
  ///
  /// Cas de vérification : 26 °C dans 40 m3 avec une rotation de 5 h 20
  /// donne max(13 h ; 5 h 20) = 13 h.
  static Duration recommendedDuration({
    required double temperatureC,
    required Duration turnover,
  }) {
    final double hoursFromTemperature = temperatureC / temperatureDivisor;
    int minutes = (hoursFromTemperature * 60).round();
    if (minutes < turnover.inMinutes) {
      minutes = turnover.inMinutes;
    }
    if (minutes < minimumMinutes) {
      minutes = minimumMinutes;
    }
    if (minutes > maximumAutomaticMinutes) {
      minutes = maximumAutomaticMinutes;
    }
    return Duration(minutes: minutes);
  }

  /// Nombre de créneaux pour une durée donnée.
  static int cycleCount(int totalMinutes) {
    if (totalMinutes <= 0) {
      return 0;
    }
    if (totalMinutes <= singleCycleMaxMinutes) {
      return 1;
    }
    if (totalMinutes <= twoCyclesMaxMinutes) {
      return 2;
    }
    return 3;
  }

  /// Découpe une durée totale en créneaux placés dans la journée.
  ///
  /// Invariant : la somme des durées des créneaux est exactement egale à
  /// `totalMinutes`. Le dernier créneau absorbe le reste de la division, sinon
  /// les arrondis feraient perdre ou gagner quelques minutes.
  static List<FiltrationCycle> splitIntoCycles(int totalMinutes) {
    if (totalMinutes <= 0) {
      return const <FiltrationCycle>[];
    }

    final int count = cycleCount(totalMinutes);
    final List<double> shares;
    if (count == 1) {
      shares = _oneCycleShares;
    } else if (count == 2) {
      shares = _twoCycleShares;
    } else {
      shares = _threeCycleShares;
    }

    final List<FiltrationCycle> cycles = <FiltrationCycle>[];
    int remaining = totalMinutes;
    for (int i = 0; i < shares.length; i++) {
      final bool isLast = i == shares.length - 1;
      final _Window window = _windows[i];
      int duration;
      if (isLast) {
        // Le dernier créneau prend tout ce qui reste : l'invariant de somme
        // passe avant le respect exact des parts.
        duration = remaining;
      } else {
        duration = (totalMinutes * shares[i]).round();
        if (duration > window.widthMinutes) {
          duration = window.widthMinutes;
        }
        if (duration > remaining) {
          duration = remaining;
        }
      }
      if (duration <= 0) {
        continue;
      }
      final int start =
          (window.centerMinute - duration ~/ 2 + minutesPerDay) % minutesPerDay;
      cycles.add(
        FiltrationCycle(startMinuteOfDay: start, durationMinutes: duration),
      );
      remaining -= duration;
    }

    // Présentation dans l'ordre chronologique de la journée.
    cycles.sort(
      (FiltrationCycle a, FiltrationCycle b) =>
          a.startMinuteOfDay.compareTo(b.startMinuteOfDay),
    );
    return List<FiltrationCycle>.unmodifiable(cycles);
  }

  /// Planning complet pour une configuration et une température d'eau.
  static FiltrationSchedule plan({
    required PoolConfig config,
    required double temperatureC,
    FiltrationMode mode = FiltrationMode.automatic,
  }) {
    final Duration turnover = turnoverTime(
      volumeM3: config.volumeM3,
      flowM3PerHour: config.pumpFlowM3PerHour,
      efficiency: config.pumpEfficiency,
    );

    switch (mode) {
      case FiltrationMode.off:
        return FiltrationSchedule(
          mode: FiltrationMode.off,
          cycles: const <FiltrationCycle>[],
          waterTemperatureC: temperatureC,
          turnoverMinutes: turnover.inMinutes,
        );
      case FiltrationMode.continuous:
        return FiltrationSchedule(
          mode: FiltrationMode.continuous,
          cycles: const <FiltrationCycle>[
            FiltrationCycle(
              startMinuteOfDay: 0,
              durationMinutes: minutesPerDay,
            ),
          ],
          waterTemperatureC: temperatureC,
          recommendedMinutes: minutesPerDay,
          turnoverMinutes: turnover.inMinutes,
        );
      case FiltrationMode.manual:
      case FiltrationMode.automatic:
        final Duration recommended = recommendedDuration(
          temperatureC: temperatureC,
          turnover: turnover,
        );
        return FiltrationSchedule(
          mode: mode,
          cycles: splitIntoCycles(recommended.inMinutes),
          waterTemperatureC: temperatureC,
          recommendedMinutes: recommended.inMinutes,
          turnoverMinutes: turnover.inMinutes,
        );
    }
  }

  /// Explication affichable de la durée retenue.
  static String explain({
    required double temperatureC,
    required Duration turnover,
    required Duration recommended,
  }) {
    final String recommendedText = FiltrationCycle.formatDuration(
      recommended.inMinutes,
    );
    final String turnoverText = FiltrationCycle.formatDuration(
      turnover.inMinutes,
    );
    final String temperatureText = temperatureC
        .toStringAsFixed(1)
        .replaceAll('.', ',');

    final int fromTemperature = (temperatureC / temperatureDivisor * 60)
        .round();
    if (fromTemperature < turnover.inMinutes) {
      return 'À $temperatureText °C la règle de la moitié de la température '
          'donnerait ${FiltrationCycle.formatDuration(fromTemperature)}, mais '
          'il faut au moins une rotation complète du bassin ($turnoverText) '
          'pour que toute l’eau passe dans le filtre. Retenu : '
          '$recommendedText.';
    }
    return 'À $temperatureText °C, la moitié de la température donne '
        '$recommendedText de filtration. Une rotation complète du volume prend '
        '$turnoverText, le bassin est donc filtré '
        '${(recommended.inMinutes / turnover.inMinutes).toStringAsFixed(1).replaceAll('.', ',')} '
        'fois dans la journée.';
  }
}
