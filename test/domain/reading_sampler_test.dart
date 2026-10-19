import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/domain/reading_sampler.dart';
import 'package:mypool/models/water_reading.dart';

final DateTime _start = DateTime.utc(2026, 7, 15, 10);

void main() {
  group('addendum § 5 : au plus une mesure par heure', () {
    test('la première mesure de sonde est toujours enregistrée', () {

      final WaterReading? sampled = ReadingSampler.sample(
        at: _start,
        lastRecorded: null,
        ph: 7.24,
        temperatureC: 26.4,
      );

      expect(sampled, isNotNull);
      expect(sampled!.ph, 7.24);
      expect(sampled.temperature, 26.4);
      expect(sampled.takenAt, _start);

      expect(sampled.source, MeasurementSource.sensor);
    });

    test('une mesure avant l’heure est refusée, même en cas de forte '
        'variation', () {
      final WaterReading last = WaterReading(
        takenAt: _start,
        ph: 7.2,
        temperature: 26.0,
        source: MeasurementSource.sensor,
      );

      expect(
        ReadingSampler.sample(
          at: _start.add(const Duration(minutes: 59)),
          lastRecorded: last,
          ph: 8.0,
          temperatureC: 30.0,
        ),
        isNull,
      );
    });

    test('à une heure pile, la mesure devient éligible', () {
      final WaterReading last = WaterReading(
        takenAt: _start,
        ph: 7.2,
        temperature: 26.0,
        source: MeasurementSource.sensor,
      );

      expect(
        ReadingSampler.sample(
          at: _start.add(const Duration(hours: 1)),
          lastRecorded: last,
          ph: 7.4,
          temperatureC: 26.0,
        ),
        isNotNull,
      );
      expect(ReadingSampler.minimumInterval, const Duration(hours: 1));
    });
  });

  group('addendum § 5 : seuils de variation', () {
    late WaterReading last;

    setUp(() {
      last = WaterReading(
        takenAt: _start,
        ph: 7.2,
        temperature: 26.0,
        source: MeasurementSource.sensor,
      );
    });

    WaterReading? sampleAfterAnHour({double? ph, double? temperatureC}) {
      return ReadingSampler.sample(
        at: _start.add(const Duration(hours: 2)),
        lastRecorded: last,
        ph: ph,
        temperatureC: temperatureC,
      );
    }

    test('une eau stable n’ajoute rien à l’historique', () {

      expect(sampleAfterAnHour(ph: 7.2, temperatureC: 26.0), isNull);

      expect(sampleAfterAnHour(ph: 7.25, temperatureC: 26.2), isNull);
    });

    test('0,1 unité de pH suffit', () {

      expect(sampleAfterAnHour(ph: 7.3, temperatureC: 26.0), isNotNull);

      expect(sampleAfterAnHour(ph: 7.1, temperatureC: 26.0), isNotNull);

      expect(sampleAfterAnHour(ph: 7.29, temperatureC: 26.0), isNull);
      expect(ReadingSampler.phDelta, 0.1);
    });

    test('l’écart de pH est arrondi au centième avant comparaison', () {

      expect(7.3 - 7.2, lessThan(0.1));
      expect(ReadingSampler.hasMoved(lastRecorded: last, ph: 7.3), isTrue);
    });

    test('0,5 °C suffit', () {

      expect(sampleAfterAnHour(ph: 7.2, temperatureC: 26.5), isNotNull);
      expect(sampleAfterAnHour(ph: 7.2, temperatureC: 25.5), isNotNull);

      expect(sampleAfterAnHour(ph: 7.2, temperatureC: 26.4), isNull);
      expect(ReadingSampler.temperatureDelta, 0.5);
    });

    test('une seule des deux valeurs suffit à déclencher', () {

      expect(sampleAfterAnHour(ph: 7.5, temperatureC: 26.0), isNotNull);

      expect(sampleAfterAnHour(ph: 7.2, temperatureC: 28.0), isNotNull);
    });

    test('une valeur inconnue jusqu’ici est une information nouvelle', () {
      final WaterReading phOnly = WaterReading(
        takenAt: _start,
        ph: 7.2,
        source: MeasurementSource.sensor,
      );

      expect(
        ReadingSampler.sample(
          at: _start.add(const Duration(hours: 2)),
          lastRecorded: phOnly,
          ph: 7.2,
          temperatureC: 26.0,
        ),
        isNotNull,
      );
    });

    test('une valeur qui disparaît ne déclenche rien', () {

      expect(ReadingSampler.hasMoved(lastRecorded: last, ph: 7.2), isFalse);
    });
  });

  group('trames sans mesure', () {
    test('une trame sans pH ni température n’est jamais enregistrée', () {
      expect(ReadingSampler.sample(at: _start, lastRecorded: null), isNull);
      expect(
        ReadingSampler.sample(
          at: _start.add(const Duration(days: 1)),
          lastRecorded: WaterReading(takenAt: _start, ph: 7.2),
        ),
        isNull,
      );
    });
  });

  group('enchaînement réaliste', () {
    test('une journée de télémétrie toutes les 2 s donne peu de points', () {

      WaterReading? last;
      int recorded = 0;

      for (int step = 0; step < 43200; step++) {
        final DateTime at = _start.add(Duration(seconds: step * 2));

        final double ph = 7.20 + (step * 2 / 3600) * 0.01;
        final WaterReading? sampled = ReadingSampler.sample(
          at: at,
          lastRecorded: last,
          ph: double.parse(ph.toStringAsFixed(2)),
          temperatureC: 26.0,
        );
        if (sampled != null) {
          recorded++;
          last = sampled;
        }
      }

      expect(recorded, lessThan(10));
      expect(recorded, greaterThan(0));
    });
  });
}
