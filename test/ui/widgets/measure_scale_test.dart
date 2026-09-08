import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/models/water_reading.dart';
import 'package:mypool/ui/theme.dart';
import 'package:mypool/ui/widgets/measure_scale.dart';
import 'package:mypool/ui/widgets/reading_row.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(child: SizedBox(width: 340, child: child)),
      ),
    );
  }

  group('règle de mesure', () {
    testWidgets('elle affiche les trois graduations du nuancier', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const MeasureScale(parameter: WaterParameter.ph, value: 7.2)),
      );

      // Les bornes acceptables aux extrémités, la plage conseillée au centre.
      expect(find.text('6,8'), findsOneWidget);
      expect(find.text('7,6'), findsOneWidget);
      expect(find.text('7,0 – 7,4'), findsOneWidget);
    });

    testWidgets('les graduations portent la virgule décimale', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const MeasureScale(parameter: WaterParameter.salt, value: 4.0)),
      );
      expect(find.text('2,5'), findsOneWidget);
      expect(find.text('3,0 – 5,0'), findsOneWidget);
    });

    testWidgets('un paramètre entier n’affiche pas de décimale', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const MeasureScale(parameter: WaterParameter.tac, value: 100)),
      );
      expect(find.text('60'), findsOneWidget);
      expect(find.text('80 – 120'), findsOneWidget);
    });

    testWidgets('sans mesure, l’échelle est grisée et sans repère', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const MeasureScale(parameter: WaterParameter.ph, value: null)),
      );
      await tester.pumpAndSettle();

      // Un repère à zéro laisserait croire à une mesure. Les graduations
      // restent, elles disent où se situe la plage conseillée.
      expect(find.text('7,0 – 7,4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('une valeur hors échelle ne fait pas déborder le repère', (
      WidgetTester tester,
    ) async {
      // Un pH de 9,5 est très au-delà de la plage acceptable : le repère doit
      // se coller au bord, pas sortir du widget.
      for (final double value in <double>[0.0, 9.5, -3.0, 99.0]) {
        await tester.pumpWidget(
          wrap(MeasureScale(parameter: WaterParameter.ph, value: value)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'pH $value');
      }
    });

    testWidgets('chaque paramètre a son nuancier', (WidgetTester tester) async {
      // Les couleurs viennent des vrais réactifs, et il y en a pour tous les
      // paramètres : un nuancier manquant ferait planter l'affichage.
      for (final WaterParameter parameter in WaterParameter.values) {
        expect(
          AppTheme.scaleFor(parameter).length,
          greaterThanOrEqualTo(2),
          reason: parameter.name,
        );
        await tester.pumpWidget(
          wrap(MeasureScale(parameter: parameter, value: parameter.target)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: parameter.name);
      }
    });

    testWidgets('les graduations peuvent être masquées', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const MeasureScale(
            parameter: WaterParameter.ph,
            value: 7.2,
            showBounds: false,
          ),
        ),
      );
      expect(find.text('7,0 – 7,4'), findsNothing);
    });
  });

  group('ligne de mesure', () {
    testWidgets('elle montre le nom, la valeur et l’état', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const ReadingRow(parameter: WaterParameter.ph, value: 7.2)),
      );

      expect(find.text('PH'), findsOneWidget);
      expect(find.text('7,2'), findsOneWidget);
      expect(find.text('dans la plage'), findsOneWidget);
    });

    testWidgets('l’unité est séparée du chiffre', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(const ReadingRow(parameter: WaterParameter.tac, value: 100)),
      );
      // L'unité est dans le même bloc que le chiffre, mais à 42 % de sa
      // taille : un « mg/L » aussi gros que « 100 » pèserait autant que la
      // mesure.
      expect(find.textContaining('100'), findsWidgets);
      expect(find.textContaining('mg/L'), findsWidgets);
    });

    testWidgets('non mesuré s’écrit en mots, jamais en zéro ni en tiret', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const ReadingRow(parameter: WaterParameter.tac, value: null)),
      );
      // Deux fois « non mesuré » : à la place de la valeur et comme état.
      expect(find.text('non mesuré'), findsNWidgets(2));
      expect(find.text('0'), findsNothing);
      // Un tiret rendu en grande taille devient un trait plein qu'on prend
      // pour un élément d'interface en panne.
      expect(find.text('—'), findsNothing);
    });

    testWidgets('l’âge de la mesure est affiché quand il compte', (
      WidgetTester tester,
    ) async {
      // Un TAC de trois semaines n'a pas la même valeur qu'un TAC d'hier, et
      // le savoir change la confiance qu'on accorde à la dose calculée.
      const Map<String, Duration> cases = <String, Duration>{
        'à l’instant': Duration(seconds: 30),
        'il y a 40 min': Duration(minutes: 40),
        'il y a 5 h': Duration(hours: 5),
        'il y a 3 jours': Duration(days: 3),
        'il y a 1 jour': Duration(days: 1),
      };

      for (final String label in cases.keys) {
        await tester.pumpWidget(
          wrap(
            ReadingRow(
              parameter: WaterParameter.tac,
              value: 100,
              age: cases[label],
            ),
          ),
        );
        expect(find.textContaining(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('la ligne est actionnable quand on lui donne une action', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        wrap(
          ReadingRow(
            parameter: WaterParameter.tac,
            value: 100,
            onTap: () => taps++,
          ),
        ),
      );

      await tester.tap(find.byType(ReadingRow));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });
}
