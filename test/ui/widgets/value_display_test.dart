import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/ui/theme.dart';
import 'package:mypool/ui/widgets/value_display.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: SizedBox(width: 340, child: child)),
  );

  group('valeur et unité', () {
    test('l’unité fait nettement moins de la moitié du chiffre', () {
      // Vu sur appareil : un « % » de la taille du nombre pèse autant que la
      // mesure et déséquilibre toute la carte.
      expect(ValueDisplay.unitScale, lessThan(0.5));
      expect(ValueDisplay.unitScale, greaterThan(0.3));
    });

    testWidgets('l’unité suit le chiffre avec un espace fin', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const ValueDisplay(value: '22', unit: '%', size: ValueSize.large)),
      );
      // « 22 % » et non « 22% », comme le veut la typographie française.
      final RichText rich = tester.widget<RichText>(find.byType(RichText));
      expect(rich.text.toPlainText(), '22\u202F%');
    });

    testWidgets('la valeur et l’unité forment un seul bloc', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const ValueDisplay(value: '26,4', unit: '°C')),
      );
      // Un seul RichText : le chiffre et l'unité ne peuvent pas se désaligner
      // ni se retrouver sur deux lignes.
      expect(find.byType(RichText), findsOneWidget);
      expect(find.textContaining('26,4'), findsOneWidget);
    });

    testWidgets('sans unité, rien n’est ajouté', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const ValueDisplay(value: '13 h')));
      // Aucune unité ajoutée : le texte rendu est exactement la valeur.
      expect(find.text('13 h'), findsOneWidget);
    });
  });

  group('absence de valeur', () {
    testWidgets('elle s’écrit en mots, jamais en tiret géant', (
      WidgetTester tester,
    ) async {
      // C'est le défaut le plus visible relevé sur appareil : un « — » rendu
      // en 76 px devient un trait plein qu'on prend pour une barre de
      // chargement en panne.
      await tester.pumpWidget(
        wrap(const ValueDisplay(value: null, size: ValueSize.large)),
      );

      expect(find.text('non mesuré'), findsOneWidget);
      expect(find.text('—'), findsNothing);
      // Et à la taille du texte courant, pas à celle d'une mesure.
      final Text text = tester.widget<Text>(find.text('non mesuré'));
      expect(text.style!.fontSize, lessThan(24));
    });

    testWidgets('le libellé du vide est personnalisable', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const ValueDisplay(value: null, emptyLabel: 'pas de sonde')),
      );
      expect(find.text('pas de sonde'), findsOneWidget);
    });
  });

  group('état vide d’une carte', () {
    testWidgets('il dit ce qui manque et comment l’obtenir', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const EmptyValue(
            label: 'Température inconnue',
            hint: 'Mesurez-la pour obtenir un planning.',
          ),
        ),
      );

      // Un écran vide est une invitation à agir, pas un cul-de-sac.
      expect(find.text('Température inconnue'), findsOneWidget);
      expect(find.text('Mesurez-la pour obtenir un planning.'), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
    });

    testWidgets('l’indication est facultative', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const EmptyValue(label: 'Rien à afficher')));
      expect(find.text('Rien à afficher'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('résistance aux grandes polices', () {
    testWidgets('un nombre long ne déborde pas à 200 % de police', (
      WidgetTester tester,
    ) async {
      // C'est le réglage qui a révélé les défauts de mise en page sur
      // appareil : à cette échelle, un nombre non contraint sort de sa carte.
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: wrap(
            const SizedBox(
              width: 120,
              child: ValueDisplay(
                value: '4294967295',
                unit: 'mg/L',
                size: ValueSize.large,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
