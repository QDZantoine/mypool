import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/domain/filtration_planner.dart';
import 'package:mypool/models/filtration_schedule.dart';
import 'package:mypool/models/pool_config.dart';

void main() {
  /// Piscine de référence de l'annexe À : 40 m3, pompe 10 m3/h à 75 %.
  const PoolConfig pool = PoolConfig();

  group('annexe À.7 - rotation du volume', () {
    test('40 m3 avec pompe 10 m3/h à 75 % = 5 h 20 de rotation', () {
      final Duration turnover = FiltrationPlanner.turnoverTime(
        volumeM3: 40.0,
        flowM3PerHour: 10.0,
        efficiency: 0.75,
      );

      // débit utile = 10 x 0,75 = 7,5 m3/h
      // rotation = 40 / 7,5 = 5,3333 h = 320 min
      expect(turnover.inMinutes, 320);
      expect(FiltrationCycle.formatDuration(320), '5 h 20');
      // Le débit utile est aussi expose par la configuration.
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

      // 26 / 2 = 13 h = 780 min, superieur à la rotation de 320 min
      expect(recommended.inMinutes, 780);
      expect(FiltrationCycle.formatDuration(780), '13 h');
    });

    test('la durée ne descend jamais sous une rotation complète', () {
      const Duration turnover = Duration(minutes: 320);
      // 8 / 2 = 4 h = 240 min, inferieur à la rotation de 320 min :
      // sans ce plancher, une partie de l’eau ne verrait jamais le filtre.
      expect(
        FiltrationPlanner.recommendedDuration(
          temperatureC: 8.0,
          turnover: turnover,
        ).inMinutes,
        320,
      );
    });

    test('plancher absolu de 2 h et plafond de 20 h', () {
      // 1 / 2 = 0,5 h = 30 min, relevé au plancher de 120 min.
      expect(
        FiltrationPlanner.recommendedDuration(
          temperatureC: 1.0,
          turnover: Duration.zero,
        ).inMinutes,
        FiltrationPlanner.minimumMinutes,
      );
      // 50 / 2 = 25 h, ramené au plafond de 1 200 min.
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
      // Durées attendues, règle température / 2 avec plancher de rotation
      // (320 min pour la piscine de référence) :
      //   8 °C -> max(240 ; 320) = 320 min -> 1 créneau
      //  14 °C -> max(420 ; 320) = 420 min -> 2 créneaux
      //  20 °C -> max(600 ; 320) = 600 min -> 2 créneaux
      //  26 °C -> max(780 ; 320) = 780 min -> 3 créneaux
      //  29 °C -> max(870 ; 320) = 870 min -> 3 créneaux
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
        // L’invariant du découpage : le dernier créneau absorbe le reste de la
        // division, la somme est donc exacte à la minute.
        expect(
          schedule.totalMinutes,
          minutes,
          reason: 'somme des creneaux a $temperature °C',
        );
        expect(schedule.cycles, isNotEmpty);
      }
    });

    test('nombre de créneaux selon la durée', () {
      // <= 6 h : un seul créneau, couper coute plus qu’il ne rapporte.
      expect(FiltrationPlanner.cycleCount(320), 1);
      expect(FiltrationPlanner.cycleCount(360), 1);
      // <= 12 h : deux créneaux.
      expect(FiltrationPlanner.cycleCount(361), 2);
      expect(FiltrationPlanner.cycleCount(720), 2);
      // au-delà : trois créneaux.
      expect(FiltrationPlanner.cycleCount(721), 3);
      expect(FiltrationPlanner.cycleCount(1200), 3);
      expect(FiltrationPlanner.cycleCount(0), 0);
    });

    test('13 h se decoupent en 390 / 234 / 156 min', () {
      final List<FiltrationCycle> cycles = FiltrationPlanner.splitIntoCycles(
        780,
      );

      // parts 50 / 30 / 20 : round(0,50 x 780) = 390, round(0,30 x 780) = 234,
      // le dernier prend 780 - 390 - 234 = 156
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

      // 390 min centres sur 14:00 -> depart à 840 - 195 = 645 min = 10:45
      expect(longest.durationMinutes, 390);
      expect(longest.startMinuteOfDay, 645);
      expect(longest.formattedStart, '10:45');
      // fin à 645 + 390 = 1 035 min = 17:15, le pic de chaleur est couvert
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
      // Les créneaux sont places dans des fenêtres disjointes de la journée ;
      // l’invariant doit tenir sur toute la plage de durées possibles.
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
      // Au-delà du plafond du mode automatique, la part de journée (50 % de
      // 1 440 = 720 min) depasserait la fenêtre de 09:00-19:00. Elle est
      // ramenée à 600 min, et l’invariant de somme tient quand même.
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
      // 780 / 320 = 2,44 rotations du volume dans la journée
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
      // Sans rotation planifiee, le compte de rotations est nul.
      expect(schedule.turnoverCount, 0.0);
    });

    test('une pompe plus puissante raccourcit la rotation, pas la durée', () {
      // 20 m3/h à 75 % = 15 m3/h utiles -> 40 / 15 = 2,667 h = 160 min
      final FiltrationSchedule schedule = FiltrationPlanner.plan(
        config: pool.copyWith(pumpFlowM3PerHour: 20.0),
        temperatureC: 26.0,
      );

      expect(schedule.turnoverMinutes, 160);
      // La durée reste dictee par la température : 26 / 2 = 13 h.
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
      // 780 / 320 = 2,4 rotations
      expect(text, contains('2,4'));
    });

    test('cas ou la rotation commande la durée', () {
      final String text = FiltrationPlanner.explain(
        temperatureC: 8.0,
        turnover: const Duration(minutes: 320),
        recommended: const Duration(minutes: 320),
      );

      // 8 / 2 = 4 h, relevé à la rotation de 5 h 20.
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
