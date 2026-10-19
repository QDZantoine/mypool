import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/domain/filtration_planner.dart';
import 'package:mypool/models/filtration_schedule.dart';
import 'package:mypool/models/pool_config.dart';

void main() {

  const PoolConfig pool = PoolConfig();

  group('annexe À.7 - rotation du volume', () {
    test('40 m3 avec pompe 10 m3/h à 75 % = 5 h 20 de rotation', () {
      final Duration turnover = FiltrationPlanner.turnoverTime(
        volumeM3: 40.0,
        flowM3PerHour: 10.0,
        efficiency: 0.75,
      );

      expect(turnover.inMinutes, 320);
      expect(FiltrationCycle.formatDuration(320), '5 h 20');

      expect(pool.effectiveFlowM3PerHour, closeTo(7.5, 1e-9));
    });

    test('rotation nulle si le débit ou le volume est nul', () {
      expect(
        FiltrationPlanner.turnoverTime(
          volumeM3: 0.0,
          flowM3PerHour: 10.0,
          efficiency: 0.75,
        ),
        Duration.zero,
      );
      expect(
        FiltrationPlanner.turnoverTime(
          volumeM3: 40.0,
          flowM3PerHour: 0.0,
          efficiency: 0.75,
        ),
        Duration.zero,
      );
    });
  });

  group('annexe À.7 - durée recommandee', () {
    test('26 °C dans 40 m3 = 13 h de filtration', () {
      const Duration turnover = Duration(minutes: 320);
      final Duration recommended = FiltrationPlanner.recommendedDuration(
        temperatureC: 26.0,
        turnover: turnover,
      );

      expect(recommended.inMinutes, 780);
      expect(FiltrationCycle.formatDuration(780), '13 h');
    });

    test('la durée ne descend jamais sous une rotation complète', () {
      const Duration turnover = Duration(minutes: 320);

      expect(
        FiltrationPlanner.recommendedDuration(
          temperatureC: 8.0,
          turnover: turnover,
        ).inMinutes,
        320,
      );
    });

    test('plancher absolu de 2 h et plafond de 20 h', () {

      expect(
        FiltrationPlanner.recommendedDuration(
          temperatureC: 1.0,
          turnover: Duration.zero,
        ).inMinutes,
        FiltrationPlanner.minimumMinutes,
      );

      expect(
        FiltrationPlanner.recommendedDuration(
          temperatureC: 50.0,
          turnover: Duration.zero,
        ).inMinutes,
        FiltrationPlanner.maximumAutomaticMinutes,
      );
    });
  });

  group('annexe À.7 - découpage en créneaux', () {
    test('somme des créneaux = durée recommandee, à chaque température', () {

      const List<List<double>> expected = <List<double>>[
        <double>[8.0, 320.0],
        <double>[14.0, 420.0],
        <double>[20.0, 600.0],
        <double>[26.0, 780.0],
        <double>[29.0, 870.0],
      ];

      for (final List<double> row in expected) {
        final double temperature = row[0];
        final int minutes = row[1].toInt();
        final FiltrationSchedule schedule = FiltrationPlanner.plan(
          config: pool,
          temperatureC: temperature,
        );

        expect(
          schedule.recommendedMinutes,
          minutes,
          reason: 'duree a $temperature °C',
        );

        expect(
          schedule.totalMinutes,
          minutes,
          reason: 'somme des creneaux a $temperature °C',
        );
        expect(schedule.cycles, isNotEmpty);
      }
    });

    test('nombre de créneaux selon la durée', () {

      expect(FiltrationPlanner.cycleCount(320), 1);
      expect(FiltrationPlanner.cycleCount(360), 1);

      expect(FiltrationPlanner.cycleCount(361), 2);
      expect(FiltrationPlanner.cycleCount(720), 2);

      expect(FiltrationPlanner.cycleCount(721), 3);
      expect(FiltrationPlanner.cycleCount(1200), 3);
      expect(FiltrationPlanner.cycleCount(0), 0);
    });

    test('13 h se decoupent en 390 / 234 / 156 min', () {
      final List<FiltrationCycle> cycles = FiltrationPlanner.splitIntoCycles(
        780,
      );

      expect(cycles.length, 3);
      expect(
        cycles.map((FiltrationCycle c) => c.durationMinutes).toList()..sort(),
        <int>[156, 234, 390],
      );
      expect(
        cycles.fold<int>(
          0,
          (int sum, FiltrationCycle c) => sum + c.durationMinutes,
        ),
        780,
      );
    });

    test('le créneau le plus long est celui de la journée', () {
      final List<FiltrationCycle> cycles = FiltrationPlanner.splitIntoCycles(
        780,
      );
      final FiltrationCycle longest = cycles.reduce(
        (FiltrationCycle a, FiltrationCycle b) =>
            a.durationMinutes >= b.durationMinutes ? a : b,
      );

      expect(longest.durationMinutes, 390);
      expect(longest.startMinuteOfDay, 645);
      expect(longest.formattedStart, '10:45');

      expect(longest.formattedEnd, '17:15');
    });

    test('les créneaux sont rendus dans l’ordre chronologique', () {
      final List<FiltrationCycle> cycles = FiltrationPlanner.splitIntoCycles(
        780,
      );
      for (int i = 1; i < cycles.length; i++) {
        expect(
          cycles[i].startMinuteOfDay,
          greaterThan(cycles[i - 1].startMinuteOfDay),
        );
      }
    });

    test('les créneaux ne se chevauchent jamais', () {

      for (
        int minutes = 1;
        minutes <= FiltrationPlanner.maximumAutomaticMinutes;
        minutes++
      ) {
        final List<FiltrationCycle> cycles = FiltrationPlanner.splitIntoCycles(
          minutes,
        );
        expect(
          cycles.fold<int>(
            0,
            (int sum, FiltrationCycle c) => sum + c.durationMinutes,
          ),
          minutes,
          reason: 'somme pour $minutes min',
        );
        for (int i = 1; i < cycles.length; i++) {
          final FiltrationCycle previous = cycles[i - 1];
          final int previousEnd =
              previous.startMinuteOfDay + previous.durationMinutes;
          expect(
            cycles[i].startMinuteOfDay,
            greaterThanOrEqualTo(previousEnd),
            reason: 'chevauchement pour $minutes min',
          );
        }
      }
    });

    test('un créneau ne dépasse jamais la largeur de sa fenêtre', () {

      final List<FiltrationCycle> cycles = FiltrationPlanner.splitIntoCycles(
        1440,
      );

      expect(
        cycles.fold<int>(
          0,
          (int sum, FiltrationCycle c) => sum + c.durationMinutes,
        ),
        1440,
      );
      final int longest = cycles
          .map((FiltrationCycle c) => c.durationMinutes)
          .reduce((int a, int b) => a >= b ? a : b);
      expect(longest, lessThanOrEqualTo(600));
    });

    test('durée nulle -> aucun créneau', () {
      expect(FiltrationPlanner.splitIntoCycles(0), isEmpty);
      expect(FiltrationPlanner.splitIntoCycles(-10), isEmpty);
    });
  });

  group('planning complet', () {
    test('mode automatique à 26 °C', () {
      final FiltrationSchedule schedule = FiltrationPlanner.plan(
        config: pool,
        temperatureC: 26.0,
      );

      expect(schedule.mode, FiltrationMode.automatic);
      expect(schedule.waterTemperatureC, 26.0);
      expect(schedule.turnoverMinutes, 320);
      expect(schedule.recommendedMinutes, 780);
      expect(schedule.formattedTotal, '13 h');
      expect(schedule.formattedTurnover, '5 h 20');

      expect(schedule.turnoverCount, closeTo(2.4375, 0.0001));
    });

    test('mode continu : un créneau de 24 h', () {
      final FiltrationSchedule schedule = FiltrationPlanner.plan(
        config: pool,
        temperatureC: 30.0,
        mode: FiltrationMode.continuous,
      );

      expect(schedule.cycles.length, 1);
      expect(schedule.totalMinutes, 1440);
      expect(schedule.recommendedMinutes, 1440);
    });

    test('mode arrêté : aucun créneau, la rotation reste connue', () {
      final FiltrationSchedule schedule = FiltrationPlanner.plan(
        config: pool,
        temperatureC: 5.0,
        mode: FiltrationMode.off,
      );

      expect(schedule.cycles, isEmpty);
      expect(schedule.totalMinutes, 0);
      expect(schedule.recommendedMinutes, 0);
      expect(schedule.turnoverMinutes, 320);

      expect(schedule.turnoverCount, 0.0);
    });

    test('une pompe plus puissante raccourcit la rotation, pas la durée', () {

      final FiltrationSchedule schedule = FiltrationPlanner.plan(
        config: pool.copyWith(pumpFlowM3PerHour: 20.0),
        temperatureC: 26.0,
      );

      expect(schedule.turnoverMinutes, 160);

      expect(schedule.recommendedMinutes, 780);
    });
  });

  group('explication affichable', () {
    test('cas ou la température commande la durée', () {
      final String text = FiltrationPlanner.explain(
        temperatureC: 26.0,
        turnover: const Duration(minutes: 320),
        recommended: const Duration(minutes: 780),
      );

      expect(text, contains('13 h'));
      expect(text, contains('5 h 20'));

      expect(text, contains('2,4'));
    });

    test('cas ou la rotation commande la durée', () {
      final String text = FiltrationPlanner.explain(
        temperatureC: 8.0,
        turnover: const Duration(minutes: 320),
        recommended: const Duration(minutes: 320),
      );

      expect(text, contains('4 h'));
      expect(text, contains('5 h 20'));
      expect(text, contains('rotation'));
    });
  });

  group('lisibilité des objets en journal', () {
    test('toString d’un planning et d’un créneau', () {
      final FiltrationSchedule schedule = FiltrationPlanner.plan(
        config: pool,
        temperatureC: 26.0,
      );
      expect(schedule.toString(), contains('13 h'));
      expect(schedule.toString(), contains('automatic'));
      expect(schedule.cycles.first.toString(), contains('->'));
    });
  });
}
