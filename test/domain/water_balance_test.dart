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
      // facteur température : 26 °C entre 24 (0,6) et 29 (0,7)
      //   0,6 + (26 - 24) / (29 - 24) x 0,1 = 0,64
      // facteur calcium    : log10(250) - 0,4 = 2,39794 - 0,4 = 1,99794
      // facteur alcalinité : log10(100) = 2,0
      // LSI = 7,4 + 0,64 + 1,99794 + 2,0 - 12,1 = -0,06206
      expect(index!, closeTo(-0.062, 0.001));
      expect(index, closeTo(-0.06, 0.005));
      expect(WaterBalance.verdictFor(index), WaterBalanceVerdict.balanced);
    });

    test('chaque terme de la formule pris séparément', () {
      // 0,6 + 2/5 x 0,1 = 0,64
      expect(WaterBalance.temperatureFactor(26.0), closeTo(0.64, 1e-9));
      // log10(250) - 0,4 = 1,99794
      expect(WaterBalance.calciumFactor(250.0), closeTo(1.99794, 0.00001));
      // log10(100) = 2,0 exactement
      expect(WaterBalance.alkalinityFactor(100.0), closeTo(2.0, 1e-9));
    });

    test('facteur de température aux points de la table', () {
      // Les points de la table sont rendus tels quels, sans interpolation.
      expect(WaterBalance.temperatureFactor(0.0), closeTo(0.0, 1e-9));
      expect(WaterBalance.temperatureFactor(12.0), closeTo(0.3, 1e-9));
      expect(WaterBalance.temperatureFactor(24.0), closeTo(0.6, 1e-9));
      expect(WaterBalance.temperatureFactor(29.0), closeTo(0.7, 1e-9));
      expect(WaterBalance.temperatureFactor(53.0), closeTo(1.0, 1e-9));
    });

    test('facteur de température interpolé entre deux points', () {
      // milieu de 16 (0,4) et 19 (0,5) : 17,5 -> 0,45
      expect(WaterBalance.temperatureFactor(17.5), closeTo(0.45, 1e-9));
      // 8 (0,2) -> 12 (0,3), à 10 °C : 0,2 + 2/4 x 0,1 = 0,25
      expect(WaterBalance.temperatureFactor(10.0), closeTo(0.25, 1e-9));
    });

    test('facteur de température borne hors de la table', () {
      // Extrapoler n’aurait pas de sens physique : une eau à -10 °C est gelee.
      expect(WaterBalance.temperatureFactor(-10.0), closeTo(0.0, 1e-9));
      expect(WaterBalance.temperatureFactor(90.0), closeTo(1.0, 1e-9));
    });

    test('eau agressive : TH et TAC bas', () {
      // facteur température 26 °C = 0,64
      // calcium    : log10(80) - 0,4 = 1,90309 - 0,4 = 1,50309
      // alcalinité : log10(60) = 1,77815
      // LSI = 7,0 + 0,64 + 1,50309 + 1,77815 - 12,1 = -1,17876
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
      // facteur température 29 °C = 0,7
      // calcium    : log10(400) - 0,4 = 2,60206 - 0,4 = 2,20206
      // alcalinité : log10(180) = 2,25527
      // LSI = 7,8 + 0,7 + 2,20206 + 2,25527 - 12,1 = 0,85733
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
      // La tolérance est de +/- 0,3 : exactement -0,3 et +0,3 sont equilibres.
      expect(WaterBalance.verdictFor(-0.3), WaterBalanceVerdict.balanced);
      expect(WaterBalance.verdictFor(0.3), WaterBalanceVerdict.balanced);
      expect(WaterBalance.verdictFor(-0.31), WaterBalanceVerdict.corrosive);
      expect(WaterBalance.verdictFor(0.31), WaterBalanceVerdict.scaling);
    });

    test('TAC ou TH nul : pas d’indice plutôt qu’un infini', () {
      // log10(0) vaut -infini : il se propagerait dans tout l’affichage.
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
      // Affichage : deux décimales, virgule décimale, signe moins typographique
      expect(result.formattedIndex, '−0,06');
    });

    test('fromReading exige les quatre valeurs', () {
      final DateTime takenAt = DateTime.utc(2026, 7, 15, 10);

      // Les quatre valeurs presentes : indice calculable.
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

      // TH manquant : mieux vaut ne rien afficher qu’un indice suppose.
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

      // Mesure vide : rien non plus.
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
