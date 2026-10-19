import '../models/filtration_schedule.dart';
import '../models/pool_config.dart';

class _Window {
  const _Window({required this.centerMinute, required this.widthMinutes});

  final int centerMinute;

  final int widthMinutes;
}

class FiltrationPlanner {
  static const int minutesPerDay = 24 * 60;

  static const double temperatureDivisor = 2.0;

  static const int minimumMinutes = 120;

  static const int maximumAutomaticMinutes = 1200;

  static const int singleCycleMaxMinutes = 360;

  static const int twoCyclesMaxMinutes = 720;

  static const List<double> _oneCycleShares = <double>[1.0];
  static const List<double> _twoCycleShares = <double>[0.60, 0.40];
  static const List<double> _threeCycleShares = <double>[0.50, 0.30, 0.20];

  static const List<_Window> _windows = <_Window>[
    _Window(centerMinute: 14 * 60, widthMinutes: 600),
    _Window(centerMinute: 3 * 60, widthMinutes: 480),
    _Window(centerMinute: 21 * 60, widthMinutes: 240),
  ];

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

    cycles.sort(
      (FiltrationCycle a, FiltrationCycle b) =>
          a.startMinuteOfDay.compareTo(b.startMinuteOfDay),
    );
    return List<FiltrationCycle>.unmodifiable(cycles);
  }

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
