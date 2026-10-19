import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/domain/water_balance.dart';
import 'package:mypool/models/water_reading.dart';

void main() {
  group('annexe À.6 - indice de Langelier', () {
    test('pH 7,4 / TAC 100 / TH 250 / 26 °C = -0,06, eau équilibrée', () {
      final double? index = WaterBalance.langelierIndex(
        ph: 7.4,
        tacMgL: 100.0,
        thMgL: 250.0,
        temperatureC: 26.0,
      );

      expect(index, isNotNull);

      expect(index!, closeTo(-0.062, 0.001));
      expect(index, closeTo(-0.06, 0.005));
      expect(WaterBalance.verdictFor(index), WaterBalanceVerdict.balanced);
    });

    test('chaque terme de la formule pris séparément', () {

      expect(WaterBalance.temperatureFactor(26.0), closeTo(0.64, 1e-9));

      expect(WaterBalance.calciumFactor(250.0), closeTo(1.99794, 0.00001));

      expect(WaterBalance.alkalinityFactor(100.0), closeTo(2.0, 1e-9));
    });

    test('facteur de température aux points de la table', () {

      expect(WaterBalance.temperatureFactor(0.0), closeTo(0.0, 1e-9));
      expect(WaterBalance.temperatureFactor(12.0), closeTo(0.3, 1e-9));
      expect(WaterBalance.temperatureFactor(24.0), closeTo(0.6, 1e-9));
      expect(WaterBalance.temperatureFactor(29.0), closeTo(0.7, 1e-9));
      expect(WaterBalance.temperatureFactor(53.0), closeTo(1.0, 1e-9));
    });

    test('facteur de température interpolé entre deux points', () {

      expect(WaterBalance.temperatureFactor(17.5), closeTo(0.45, 1e-9));

      expect(WaterBalance.temperatureFactor(10.0), closeTo(0.25, 1e-9));
    });

    test('facteur de température borne hors de la table', () {

      expect(WaterBalance.temperatureFactor(-10.0), closeTo(0.0, 1e-9));
      expect(WaterBalance.temperatureFactor(90.0), closeTo(1.0, 1e-9));
    });

    test('eau agressive : TH et TAC bas', () {

      final double? index = WaterBalance.langelierIndex(
        ph: 7.0,
        tacMgL: 60.0,
        thMgL: 80.0,
        temperatureC: 26.0,
      );
      expect(index!, closeTo(-1.179, 0.001));
      expect(WaterBalance.verdictFor(index), WaterBalanceVerdict.corrosive);
    });

    test('eau entartrante : pH, TH et TAC hauts', () {

      final double? index = WaterBalance.langelierIndex(
        ph: 7.8,
        tacMgL: 180.0,
        thMgL: 400.0,
        temperatureC: 29.0,
      );
      expect(index!, closeTo(0.857, 0.001));
      expect(WaterBalance.verdictFor(index), WaterBalanceVerdict.scaling);
    });

    test('les bornes de la plage d’équilibre sont incluses', () {

      expect(WaterBalance.verdictFor(-0.3), WaterBalanceVerdict.balanced);
      expect(WaterBalance.verdictFor(0.3), WaterBalanceVerdict.balanced);
      expect(WaterBalance.verdictFor(-0.31), WaterBalanceVerdict.corrosive);
      expect(WaterBalance.verdictFor(0.31), WaterBalanceVerdict.scaling);
    });

    test('TAC ou TH nul : pas d’indice plutôt qu’un infini', () {

      expect(
        WaterBalance.langelierIndex(
          ph: 7.4,
          tacMgL: 0.0,
          thMgL: 250.0,
          temperatureC: 26.0,
        ),
        isNull,
      );
      expect(
        WaterBalance.langelierIndex(
          ph: 7.4,
          tacMgL: 100.0,
          thMgL: 0.0,
          temperatureC: 26.0,
        ),
        isNull,
      );
      expect(WaterBalance.verdictFor(null), WaterBalanceVerdict.unknown);
      expect(
        WaterBalance.evaluate(
          ph: 7.4,
          tacMgL: 0.0,
          thMgL: 250.0,
          temperatureC: 26.0,
        ),
        isNull,
      );
    });
  });

  group('résultat détaillé', () {
    test('evaluate expose chaque facteur et le verdict', () {
      final WaterBalanceResult? result = WaterBalance.evaluate(
        ph: 7.4,
        tacMgL: 100.0,
        thMgL: 250.0,
        temperatureC: 26.0,
      );

      expect(result, isNotNull);
      expect(result!.index, closeTo(-0.062, 0.001));
      expect(result.temperatureFactor, closeTo(0.64, 1e-9));
      expect(result.calciumFactor, closeTo(1.99794, 0.00001));
      expect(result.alkalinityFactor, closeTo(2.0, 1e-9));
      expect(result.verdict, WaterBalanceVerdict.balanced);

      expect(result.formattedIndex, '−0,06');
    });

    test('fromReading exige les quatre valeurs', () {
      final DateTime takenAt = DateTime.utc(2026, 7, 15, 10);

      expect(
        WaterBalance.fromReading(
          WaterReading(
            takenAt: takenAt,
            ph: 7.4,
            tac: 100.0,
            th: 250.0,
            temperature: 26.0,
          ),
        )?.index,
        closeTo(-0.062, 0.001),
      );

      expect(
        WaterBalance.fromReading(
          WaterReading(
            takenAt: takenAt,
            ph: 7.4,
            tac: 100.0,
            temperature: 26.0,
          ),
        ),
        isNull,
      );

      expect(WaterBalance.fromReading(WaterReading(takenAt: takenAt)), isNull);
    });

    test('toString reste lisible en journal', () {
      final WaterBalanceResult? result = WaterBalance.evaluate(
        ph: 7.4,
        tacMgL: 100.0,
        thMgL: 250.0,
        temperatureC: 26.0,
      );
      expect(result.toString(), contains('-0.06'));
      expect(result.toString(), contains('balanced'));
    });

    test('chaque verdict à une explication non vide', () {
      for (final WaterBalanceVerdict verdict in WaterBalanceVerdict.values) {
        expect(WaterBalance.explain(verdict), isNotEmpty);
      }
    });
  });
}
