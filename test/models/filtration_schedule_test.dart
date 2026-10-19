import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/models/filtration_schedule.dart';

void main() {
  group('créneau', () {
    test('heures de debut et de fin', () {
      const FiltrationCycle cycle = FiltrationCycle(
        startMinuteOfDay: 645,
        durationMinutes: 390,
      );

      expect(cycle.formattedStart, '10:45');

      expect(cycle.endMinuteOfDay, 1035);
      expect(cycle.formattedEnd, '17:15');
      expect(cycle.duration, const Duration(minutes: 390));
    });

    test('un créneau qui passe minuit', () {
      const FiltrationCycle cycle = FiltrationCycle(
        startMinuteOfDay: 1380,
        durationMinutes: 180,
      );

      expect(cycle.formattedStart, '23:00');
      expect(cycle.endMinuteOfDay, 120);
      expect(cycle.formattedEnd, '02:00');
    });

    test('formatage des durées', () {

      expect(FiltrationCycle.formatDuration(320), '5 h 20');

      expect(FiltrationCycle.formatDuration(780), '13 h');

      expect(FiltrationCycle.formatDuration(45), '45 min');
      expect(FiltrationCycle.formatDuration(0), '0 min');

      expect(FiltrationCycle.formatDuration(365), '6 h 05');
    });

    test('formatage des heures de la journée', () {
      expect(FiltrationCycle.formatMinuteOfDay(0), '00:00');
      expect(FiltrationCycle.formatMinuteOfDay(63), '01:03');
      expect(FiltrationCycle.formatMinuteOfDay(840), '14:00');
      expect(FiltrationCycle.formatMinuteOfDay(1439), '23:59');

      expect(FiltrationCycle.formatMinuteOfDay(1500), '01:00');
    });

    test('durée du créneau exposee en Duration et en texte', () {
      const FiltrationCycle cycle = FiltrationCycle(
        startMinuteOfDay: 645,
        durationMinutes: 390,
      );

      expect(cycle.formattedDuration, '6 h 30');
      expect(cycle.toString(), contains('10:45'));
      expect(cycle == Object(), isFalse);
    });

    test('copyWith sans argument rend un objet égal', () {
      const FiltrationCycle cycle = FiltrationCycle(
        startMinuteOfDay: 645,
        durationMinutes: 390,
      );
      expect(cycle.copyWith(), cycle);
      expect(cycle.copyWith().hashCode, cycle.hashCode);
    });
  });

  group('planning', () {
    test('somme des créneaux', () {
      const FiltrationSchedule schedule = FiltrationSchedule(
        mode: FiltrationMode.automatic,
        cycles: <FiltrationCycle>[
          FiltrationCycle(startMinuteOfDay: 63, durationMinutes: 234),
          FiltrationCycle(startMinuteOfDay: 645, durationMinutes: 390),
          FiltrationCycle(startMinuteOfDay: 1182, durationMinutes: 156),
        ],
        recommendedMinutes: 780,
        turnoverMinutes: 320,
      );

      expect(schedule.totalMinutes, 780);
      expect(schedule.total, const Duration(minutes: 780));
      expect(schedule.formattedTotal, '13 h');
      expect(schedule.formattedTurnover, '5 h 20');

      expect(schedule.turnoverCount, closeTo(2.4375, 1e-9));
    });

    test('durées exposees en Duration', () {
      const FiltrationSchedule schedule = FiltrationSchedule(
        mode: FiltrationMode.automatic,
        cycles: <FiltrationCycle>[
          FiltrationCycle(startMinuteOfDay: 645, durationMinutes: 390),
        ],
        recommendedMinutes: 390,
        turnoverMinutes: 320,
      );
      expect(schedule.total, const Duration(minutes: 390));
      expect(schedule.recommended, const Duration(minutes: 390));
      expect(schedule.turnover, const Duration(minutes: 320));
      expect(schedule == Object(), isFalse);
    });

    test('planning vide', () {
      expect(FiltrationSchedule.empty.mode, FiltrationMode.off);
      expect(FiltrationSchedule.empty.cycles, isEmpty);
      expect(FiltrationSchedule.empty.totalMinutes, 0);

      expect(FiltrationSchedule.empty.turnoverCount, 0.0);
    });

    test('copyWith sans argument rend un objet égal', () {
      const FiltrationSchedule schedule = FiltrationSchedule(
        mode: FiltrationMode.automatic,
        cycles: <FiltrationCycle>[
          FiltrationCycle(startMinuteOfDay: 645, durationMinutes: 390),
        ],
        recommendedMinutes: 390,
        turnoverMinutes: 320,
      );
      expect(schedule.copyWith(), schedule);
      expect(schedule.copyWith().hashCode, schedule.hashCode);
    });

    test('deux plannings de créneaux differents ne sont pas égaux', () {
      const FiltrationSchedule a = FiltrationSchedule(
        mode: FiltrationMode.automatic,
        cycles: <FiltrationCycle>[
          FiltrationCycle(startMinuteOfDay: 645, durationMinutes: 390),
        ],
      );
      const FiltrationSchedule b = FiltrationSchedule(
        mode: FiltrationMode.automatic,
        cycles: <FiltrationCycle>[
          FiltrationCycle(startMinuteOfDay: 600, durationMinutes: 390),
        ],
      );
      expect(a, isNot(b));

      expect(
        a,
        isNot(
          const FiltrationSchedule(
            mode: FiltrationMode.automatic,
            cycles: <FiltrationCycle>[],
          ),
        ),
      );
    });
  });

  group('aller-retour JSON', () {
    test('un planning complet survit au passage par JSON', () {
      const FiltrationSchedule original = FiltrationSchedule(
        mode: FiltrationMode.automatic,
        cycles: <FiltrationCycle>[
          FiltrationCycle(startMinuteOfDay: 63, durationMinutes: 234),
          FiltrationCycle(startMinuteOfDay: 645, durationMinutes: 390),
          FiltrationCycle(startMinuteOfDay: 1182, durationMinutes: 156),
        ],
        waterTemperatureC: 26.0,
        recommendedMinutes: 780,
        turnoverMinutes: 320,
      );

      final FiltrationSchedule restored = FiltrationSchedule.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(restored, original);
      expect(restored.totalMinutes, 780);
    });

    test('un créneau survit au passage par JSON', () {
      const FiltrationCycle original = FiltrationCycle(
        startMinuteOfDay: 645,
        durationMinutes: 390,
      );

      final FiltrationCycle restored = FiltrationCycle.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(restored, original);
    });
  });

  group('JSON corrompu', () {
    test('un objet vide rend un planning automatique sans créneau', () {
      final FiltrationSchedule restored = FiltrationSchedule.fromJson(
        <String, dynamic>{},
      );

      expect(restored.mode, FiltrationMode.automatic);
      expect(restored.cycles, isEmpty);
      expect(restored.recommendedMinutes, 0);
    });

    test('null, une chaîne ou une liste rendent un planning vide', () {
      expect(FiltrationSchedule.fromJson(null).cycles, isEmpty);
      expect(FiltrationSchedule.fromJson('perdu').cycles, isEmpty);
      expect(FiltrationSchedule.fromJson(<int>[1]).cycles, isEmpty);
    });

    test('les créneaux illisibles sont ignorés, les autres conservés', () {
      final FiltrationSchedule restored = FiltrationSchedule.fromJson(
        <String, dynamic>{
          'cycles': <Object?>[
            <String, dynamic>{'startMinuteOfDay': 645, 'durationMinutes': 390},
            'pas un creneau',
            null,
            42,
          ],
        },
      );

      expect(restored.cycles.length, 1);
      expect(restored.cycles.first.startMinuteOfDay, 645);
    });

    test('une heure de depart hors journée est ramenée dans la journée', () {

      expect(
        FiltrationCycle.fromJson(<String, dynamic>{'startMinuteOfDay': 1500})
            .startMinuteOfDay,
        60,
      );
    });

    test('une durée aberrante est bornée à la journée', () {
      expect(
        FiltrationCycle.fromJson(<String, dynamic>{'durationMinutes': 99999})
            .durationMinutes,
        1440,
      );
      expect(
        FiltrationCycle.fromJson(<String, dynamic>{'durationMinutes': -60})
            .durationMinutes,
        0,
      );
    });

    test('un mode inconnu retombe sur le mode automatique', () {
      expect(
        FiltrationSchedule.fromJson(<String, dynamic>{'mode': 'a l’instinct'})
            .mode,
        FiltrationMode.automatic,
      );
    });
  });
}
