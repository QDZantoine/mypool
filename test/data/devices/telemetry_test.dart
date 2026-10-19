import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/devices/telemetry.dart';

final DateTime _receivedAt = DateTime.utc(2026, 7, 15, 10, 30);

void main() {

  const String reference = '''
{
  "deviceId": "a7f3c1e9b2",
  "ph": 7.24,
  "phRaw": 2117,
  "tempC": 26.4,
  "cover":  { "position": 0.420, "motion": "opening", "estimated": true },
  "pump":   { "on": true, "runMinutes": 312 },
  "heater": { "on": false, "auto": true, "setpointC": 27.0 },
  "filterAlert": false,
  "uptimeS": 1834
}
''';

  group('trame complète', () {
    test('la trame de référence de l’addendum est décodée entièrement', () {
      final PoolTelemetry telemetry = PoolTelemetry.fromJson(
        jsonDecode(reference),
        receivedAt: _receivedAt,
      );

      expect(telemetry.deviceId, 'a7f3c1e9b2');
      expect(telemetry.ph, 7.24);
      expect(telemetry.phRaw, 2117);
      expect(telemetry.temperatureC, 26.4);
      expect(telemetry.coverPosition, 0.420);
      expect(telemetry.coverMotion, TelemetryMotion.opening);
      expect(telemetry.coverEstimated, isTrue);
      expect(telemetry.pumpOn, isTrue);
      expect(telemetry.pumpRunMinutes, 312);
      expect(telemetry.heaterOn, isFalse);
      expect(telemetry.heaterAuto, isTrue);
      expect(telemetry.heaterSetpointC, 27.0);
      expect(telemetry.filterAlert, isFalse);
      expect(telemetry.uptimeSeconds, 1834);
      expect(telemetry.hasNoMeasurement, isFalse);
    });

    test('les trois mouvements du contrat sont reconnus', () {
      for (final String motion in <String>['idle', 'opening', 'closing']) {
        final PoolTelemetry telemetry = PoolTelemetry.fromJson(
          <String, dynamic>{
            'cover': <String, dynamic>{'motion': motion},
          },
          receivedAt: _receivedAt,
        );
        expect(telemetry.coverMotion.name, motion);
      }
    });

    test('aller-retour JSON', () {
      final PoolTelemetry original = PoolTelemetry.fromJson(
        jsonDecode(reference),
        receivedAt: _receivedAt,
      );
      final PoolTelemetry restored = PoolTelemetry.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
        receivedAt: _receivedAt,
      );

      expect(restored.toJson(), original.toJson());
      expect(restored.ph, original.ph);
      expect(restored.coverMotion, original.coverMotion);
    });

    test('copyWith ne touche que le champ demandé', () {
      final PoolTelemetry original = PoolTelemetry.fromJson(
        jsonDecode(reference),
        receivedAt: _receivedAt,
      );
      final PoolTelemetry changed = original.copyWith(ph: 7.8);
      expect(changed.ph, 7.8);
      expect(changed.temperatureC, original.temperatureC);
      expect(original.copyWith().toJson(), original.toJson());
    });

    test('toString reste lisible en journal', () {
      final PoolTelemetry telemetry = PoolTelemetry.fromJson(
        jsonDecode(reference),
        receivedAt: _receivedAt,
      );
      expect(telemetry.toString(), contains('7.24'));
      expect(telemetry.toString(), contains('opening'));
    });
  });

  group('trame partielle', () {
    test('les champs absents restent absents, ils ne valent pas zéro', () {
      final PoolTelemetry telemetry = PoolTelemetry.fromJson(<String, dynamic>{
        'deviceId': 'abc',
      }, receivedAt: _receivedAt);

      expect(telemetry.ph, isNull);
      expect(telemetry.temperatureC, isNull);
      expect(telemetry.coverPosition, isNull);
      expect(telemetry.pumpOn, isNull);
      expect(telemetry.heaterOn, isNull);
      expect(telemetry.hasNoMeasurement, isTrue);

      expect(telemetry.coverMotion, TelemetryMotion.idle);
      expect(telemetry.coverEstimated, isTrue);
      expect(telemetry.filterAlert, isFalse);
    });

    test('un sous-objet manquant ne fait pas échouer le décodage', () {
      final PoolTelemetry telemetry = PoolTelemetry.fromJson(<String, dynamic>{
        'ph': 7.2,
        'tempC': 25.0,
      }, receivedAt: _receivedAt);
      expect(telemetry.ph, 7.2);
      expect(telemetry.coverMotion, TelemetryMotion.idle);
      expect(telemetry.pumpOn, isNull);
    });

    test('un firmware plus récent peut ajouter des champs', () {

      final PoolTelemetry telemetry = PoolTelemetry.fromJson(<String, dynamic>{
        'ph': 7.2,
        'orp': 650,
        'salinity': 4.2,
      }, receivedAt: _receivedAt);
      expect(telemetry.ph, 7.2);
    });
  });

  group('trame invalide', () {
    test('null, une chaîne ou une liste donnent une trame vide', () {
      for (final Object? raw in <Object?>[
        null,
        'perdu',
        <int>[1, 2],
        42,
      ]) {
        final PoolTelemetry telemetry = PoolTelemetry.fromJson(
          raw,
          receivedAt: _receivedAt,
        );
        expect(telemetry.hasNoMeasurement, isTrue, reason: '$raw');
        expect(telemetry.deviceId, '');
      }
    });

    test('un sous-objet du mauvais type est ignoré', () {
      final PoolTelemetry telemetry = PoolTelemetry.fromJson(<String, dynamic>{
        'ph': 7.2,
        'cover': 'ouverte',
        'pump': <int>[1],
        'heater': 42,
      }, receivedAt: _receivedAt);
      expect(telemetry.ph, 7.2);
      expect(telemetry.coverMotion, TelemetryMotion.idle);
      expect(telemetry.pumpOn, isNull);
    });

    test('les valeurs hors du domaine physique deviennent absentes', () {

      final PoolTelemetry telemetry = PoolTelemetry.fromJson(<String, dynamic>{
        'ph': 900.0,
        'tempC': -300.0,
        'cover': <String, dynamic>{'position': 5.0},
        'heater': <String, dynamic>{'setpointC': 999.0},
      }, receivedAt: _receivedAt);
      expect(telemetry.ph, isNull);
      expect(telemetry.temperatureC, isNull);
      expect(telemetry.coverPosition, isNull);
      expect(telemetry.heaterSetpointC, isNull);
    });

    test('les bornes du domaine restent acceptées', () {
      final PoolTelemetry telemetry = PoolTelemetry.fromJson(<String, dynamic>{
        'ph': 14.0,
        'tempC': -50.0,
        'cover': <String, dynamic>{'position': 1.0},
      }, receivedAt: _receivedAt);
      expect(telemetry.ph, 14.0);
      expect(telemetry.temperatureC, -50.0);
      expect(telemetry.coverPosition, 1.0);
    });

    test('un mouvement inconnu retombe sur l’arrêt', () {

      final PoolTelemetry telemetry = PoolTelemetry.fromJson(<String, dynamic>{
        'cover': <String, dynamic>{'motion': 'tournoie'},
      }, receivedAt: _receivedAt);
      expect(telemetry.coverMotion, TelemetryMotion.idle);
    });

    test('les booléens écrits en nombre ou en chaîne sont lus', () {
      final PoolTelemetry telemetry = PoolTelemetry.fromJson(<String, dynamic>{
        'pump': <String, dynamic>{'on': 1},
        'heater': <String, dynamic>{'on': 'true', 'auto': 0},
      }, receivedAt: _receivedAt);
      expect(telemetry.pumpOn, isTrue);
      expect(telemetry.heaterOn, isTrue);
      expect(telemetry.heaterAuto, isFalse);
    });

    test('un booléen illisible reste absent', () {
      final PoolTelemetry telemetry = PoolTelemetry.fromJson(<String, dynamic>{
        'pump': <String, dynamic>{'on': 'peut-être'},
      }, receivedAt: _receivedAt);
      expect(telemetry.pumpOn, isNull);
    });

    test('une position estimée ne se devine pas', () {

      expect(
        PoolTelemetry.fromJson(<String, dynamic>{
          'cover': <String, dynamic>{'estimated': 'non'},
        }, receivedAt: _receivedAt).coverEstimated,
        isTrue,
      );
      expect(
        PoolTelemetry.fromJson(<String, dynamic>{
          'cover': <String, dynamic>{'estimated': false},
        }, receivedAt: _receivedAt).coverEstimated,
        isFalse,
      );
    });
  });
}
