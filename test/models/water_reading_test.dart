import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/models/filtration_schedule.dart';
import 'package:mypool/models/pool_config.dart';
import 'package:mypool/models/water_reading.dart';

final DateTime _fixedDate = DateTime.utc(2026, 7, 15, 10, 30);

void main() {
  group('plages de référence (annexe À.1)', () {
    test('pH : idéal 7,0-7,4, acceptable 6,8-7,6, cible 7,2', () {
      expect(WaterParameter.ph.idealMin, 7.0);
      expect(WaterParameter.ph.idealMax, 7.4);
      expect(WaterParameter.ph.acceptableMin, 6.8);
      expect(WaterParameter.ph.acceptableMax, 7.6);
      // On vise 7,2 : le meilleur compromis efficacité du chlore / confort.
      expect(WaterParameter.ph.target, 7.2);
    });

    test('chlore libre : 1,0-2,0 mg/L', () {
      expect(WaterParameter.freeChlorine.idealMin, 1.0);
      expect(WaterParameter.freeChlorine.idealMax, 2.0);
      expect(WaterParameter.freeChlorine.acceptableMax, 3.0);
    });

    test('chlore combiné : au-dela de 0,6 mg/L il faut un choc', () {
      expect(WaterParameter.combinedChlorine.idealMax, 0.2);
      expect(WaterParameter.combinedChlorine.acceptableMax, 0.6);
    });

    test('TAC : 80-120 mg/L', () {
      expect(WaterParameter.tac.idealMin, 80.0);
      expect(WaterParameter.tac.idealMax, 120.0);
    });

    test('TH : 100-300 mg/L', () {
      expect(WaterParameter.th.idealMin, 100.0);
      expect(WaterParameter.th.idealMax, 300.0);
    });

    test('stabilisant : 20-50 mg/L, saturé au-dela de 75', () {
      expect(WaterParameter.stabilizer.idealMin, 20.0);
      expect(WaterParameter.stabilizer.idealMax, 50.0);
      expect(WaterParameter.stabilizer.acceptableMax, 75.0);
    });

    test('sel : 3,0-5,0 g/L', () {
      expect(WaterParameter.salt.idealMin, 3.0);
      expect(WaterParameter.salt.idealMax, 5.0);
    });

    test('chaque paramètre à un libellé et une plage cohérente', () {
      for (final WaterParameter parameter in WaterParameter.values) {
        expect(parameter.label, isNotEmpty, reason: parameter.name);
        expect(
          parameter.acceptableMin,
          lessThanOrEqualTo(parameter.idealMin),
          reason: parameter.name,
        );
        expect(
          parameter.idealMin,
          lessThanOrEqualTo(parameter.idealMax),
          reason: parameter.name,
        );
        expect(
          parameter.idealMax,
          lessThanOrEqualTo(parameter.acceptableMax),
          reason: parameter.name,
        );
        // La cible est toujours dans la plage idéale.
        expect(
          parameter.target,
          inInclusiveRange(parameter.idealMin, parameter.idealMax),
          reason: parameter.name,
        );
      }
    });
  });

  group('statut d’un paramètre', () {
    test('les cinq états du pH', () {
      // 6,5 < 6,8 acceptable
      expect(WaterParameter.ph.statusOf(6.5), ParameterStatus.veryLow);
      // 6,9 entre 6,8 et 7,0
      expect(WaterParameter.ph.statusOf(6.9), ParameterStatus.low);
      expect(WaterParameter.ph.statusOf(7.2), ParameterStatus.ideal);
      // 7,5 entre 7,4 et 7,6
      expect(WaterParameter.ph.statusOf(7.5), ParameterStatus.high);
      // 7,9 > 7,6 acceptable
      expect(WaterParameter.ph.statusOf(7.9), ParameterStatus.veryHigh);
    });

    test('les bornes sont incluses dans la plage idéale', () {
      expect(WaterParameter.ph.statusOf(7.0), ParameterStatus.ideal);
      expect(WaterParameter.ph.statusOf(7.4), ParameterStatus.ideal);
    });

    test('une valeur absente est inconnue, pas nulle', () {
      // Sans cela, un pH non mesure declencherait une correction massive.
      expect(WaterParameter.ph.statusOf(null), ParameterStatus.unknown);
    });
  });

  group('formatage des valeurs', () {
    test('virgule décimale et unité', () {
      // pH : une décimale, pas d’unité
      expect(WaterParameter.ph.formatValue(7.2), '7,2');
      // chlore : une décimale et mg/L
      expect(WaterParameter.freeChlorine.formatValue(1.5), '1,5 mg/L');
      // TAC : entier
      expect(WaterParameter.tac.formatValue(100.0), '100 mg/L');
      expect(WaterParameter.th.formatValue(250.0), '250 mg/L');
      expect(WaterParameter.salt.formatValue(4.0), '4,0 g/L');
      expect(WaterParameter.temperature.formatValue(26.0), '26,0 °C');
    });
  });

  group('mesure', () {
    test('une mesure sans aucune valeur est vide', () {
      final WaterReading empty = WaterReading(takenAt: _fixedDate);
      expect(empty.isEmpty, isTrue);
      expect(empty.isNotEmpty, isFalse);
    });

    test('une seule valeur suffit à rendre la mesure non vide', () {
      // Même la température seule, qui ne declenche pourtant aucun dosage.
      expect(
        WaterReading(takenAt: _fixedDate, temperature: 26.0).isEmpty,
        isFalse,
      );
    });

    test('valueOf couvre tous les paramètres', () {
      final WaterReading reading = WaterReading(
        takenAt: _fixedDate,
        ph: 7.2,
        freeChlorine: 1.5,
        combinedChlorine: 0.1,
        tac: 100.0,
        th: 250.0,
        stabilizer: 30.0,
        salt: 4.0,
        temperature: 26.0,
      );

      for (final WaterParameter parameter in WaterParameter.values) {
        expect(reading.valueOf(parameter), isNotNull, reason: parameter.name);
        expect(
          reading.statusOf(parameter),
          ParameterStatus.ideal,
          reason: parameter.name,
        );
      }
      expect(reading.valueOf(WaterParameter.ph), 7.2);
      expect(reading.valueOf(WaterParameter.salt), 4.0);
    });

    test('statusOf rend unknown pour une valeur non saisie', () {
      final WaterReading reading = WaterReading(takenAt: _fixedDate, ph: 7.2);
      expect(reading.statusOf(WaterParameter.tac), ParameterStatus.unknown);
    });

    test('copyWith sans argument rend un objet égal', () {
      final WaterReading reading = WaterReading(takenAt: _fixedDate, ph: 7.2);
      expect(reading.copyWith(), reading);
      expect(reading.copyWith().hashCode, reading.hashCode);
    });
  });

  group('lectures JSON tolerantes', () {
    test('un entier ecrit en réel ou en chaîne reste lisible', () {
      // Les durées et compteurs sont relus par readInt : réel arrondi,
      // chaîne entière, chaîne décimale, puis repli.
      expect(
        FiltrationCycle.fromJson(<String, dynamic>{'durationMinutes': 390.4})
            .durationMinutes,
        390,
      );
      expect(
        FiltrationCycle.fromJson(<String, dynamic>{'durationMinutes': '390'})
            .durationMinutes,
        390,
      );
      expect(
        FiltrationCycle.fromJson(<String, dynamic>{'durationMinutes': '390.6'})
            .durationMinutes,
        391,
      );
      expect(
        FiltrationCycle.fromJson(<String, dynamic>{
          'durationMinutes': 'longtemps',
        }).durationMinutes,
        0,
      );
      // Un NaN n’est pas fini : repli sur le défaut.
      expect(
        FiltrationCycle.fromJson(<String, dynamic>{
          'durationMinutes': double.nan,
        }).durationMinutes,
        0,
      );
    });

    test('un booleen ecrit en nombre ou en chaîne reste lisible', () {
      // Le consentement de sécurité est relu par readBool.
      expect(
        PoolConfig.fromJson(<String, dynamic>{'safetyConsentGiven': 1})
            .safetyConsentGiven,
        isTrue,
      );
      expect(
        PoolConfig.fromJson(<String, dynamic>{'safetyConsentGiven': 0})
            .safetyConsentGiven,
        isFalse,
      );
      expect(
        PoolConfig.fromJson(<String, dynamic>{'safetyConsentGiven': 'true'})
            .safetyConsentGiven,
        isTrue,
      );
      expect(
        PoolConfig.fromJson(<String, dynamic>{'safetyConsentGiven': 'false'})
            .safetyConsentGiven,
        isFalse,
      );
    });

    test('une carte à clés non textuelles est ignoree, pas rejetee', () {
      // Un JSON relu depuis SQLite peut porter des clés numériques.
      final PoolConfig restored = PoolConfig.fromJson(<Object?, Object?>{
        1: 'parasite',
        'volumeM3': 55.0,
      });
      expect(restored.volumeM3, 55.0);
    });

    test('une mesure n’est jamais égale à un objet d’un autre type', () {
      expect(WaterReading(takenAt: _fixedDate) == Object(), isFalse);
    });
  });

  group('aller-retour JSON', () {
    test('une mesure complète survit au passage par JSON', () {
      final WaterReading original = WaterReading(
        takenAt: _fixedDate,
        ph: 7.35,
        freeChlorine: 1.8,
        combinedChlorine: 0.15,
        tac: 105.0,
        th: 240.0,
        stabilizer: 35.0,
        salt: 4.2,
        temperature: 27.5,
        note: 'après un orage',
        source: MeasurementSource.sensor,
      );

      final WaterReading restored = WaterReading.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(restored, original);
    });

    test('une mesure partielle garde ses valeurs absentes absentes', () {
      final WaterReading original = WaterReading(takenAt: _fixedDate, ph: 7.4);

      final WaterReading restored = WaterReading.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(restored, original);
      // Le point clef : absent ne devient pas zéro.
      expect(restored.tac, isNull);
      expect(restored.freeChlorine, isNull);
    });
  });

  group('JSON corrompu', () {
    test('un objet vide rend une mesure vide datee de l’époque Unix', () {
      final WaterReading restored = WaterReading.fromJson(<String, dynamic>{});
      expect(restored.isEmpty, isTrue);
      // Date fausse mais stable : le domaine ne lit jamais l’horloge.
      expect(restored.takenAt.millisecondsSinceEpoch, 0);
    });

    test('null, une chaîne ou une liste rendent une mesure vide', () {
      expect(WaterReading.fromJson(null).isEmpty, isTrue);
      expect(WaterReading.fromJson('perdu').isEmpty, isTrue);
      expect(WaterReading.fromJson(<int>[1, 2]).isEmpty, isTrue);
    });

    test('une valeur du mauvais type devient absente, pas zéro', () {
      final WaterReading restored = WaterReading.fromJson(<String, dynamic>{
        'ph': 'acide',
        'tac': <String, dynamic>{},
        'th': true,
        'freeChlorine': 1.5,
      });

      expect(restored.ph, isNull);
      expect(restored.tac, isNull);
      expect(restored.th, isNull);
      // La valeur lisible est conservee.
      expect(restored.freeChlorine, 1.5);
    });

    test('les nombres ecrits en chaîne sont acceptes', () {
      final WaterReading restored = WaterReading.fromJson(<String, dynamic>{
        'ph': '7.4',
        // Virgule décimale, comme une saisie francaise mal sérialisée.
        'tac': '105,5',
      });

      expect(restored.ph, 7.4);
      expect(restored.tac, 105.5);
    });

    test('un NaN ou un infini devient absent', () {
      // Ces valeurs se propageraient dans tous les calculs de dose.
      final WaterReading restored = WaterReading.fromJson(<String, dynamic>{
        'ph': double.nan,
        'tac': double.infinity,
      });
      expect(restored.ph, isNull);
      expect(restored.tac, isNull);
    });

    test('une date illisible retombe sur l’époque Unix', () {
      expect(
        WaterReading.fromJson(<String, dynamic>{'takenAt': 'hier'})
            .takenAt
            .millisecondsSinceEpoch,
        0,
      );
      // Un horodatage en millisecondes reste lisible.
      expect(
        WaterReading.fromJson(<String, dynamic>{'takenAt': 1770000000000})
            .takenAt
            .millisecondsSinceEpoch,
        1770000000000,
      );
    });

    test('une note vide est traitee comme absente', () {
      expect(
        WaterReading.fromJson(<String, dynamic>{'note': '  '}).note,
        isNull,
      );
    });
  });
}
