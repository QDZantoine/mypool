import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/models/water_reading.dart';
import 'package:mypool/ui/theme.dart';
import 'package:mypool/ui/widgets/measure_scale.dart';
import 'package:mypool/ui/widgets/reading_row.dart';
import 'package:mypool/ui/widgets/section_header.dart';

double _luminance(Color color) {
  double channel(double value) {
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  final double high = la > lb ? la : lb;
  final double low = la > lb ? lb : la;
  return (high + 0.05) / (low + 0.05);
}

void main() {
  group('contraste WCAG AA', () {

    test('les couleurs d’état tiennent le 4,5:1 en mode clair', () {
      AppTheme.applyBrightness(Brightness.light);
      const Color hardest = AppTheme.surface;

      final Map<String, Color> colors = <String, Color>{
        'chlorine': AppTheme.chlorine,
        'inRange': AppTheme.inRange,
        'drift': AppTheme.drift,
        'acid': AppTheme.acid,
        'unmeasured': AppTheme.unmeasured,
        'inkMuted': AppTheme.inkMuted,
      };

      colors.forEach((String name, Color color) {
        expect(
          _contrast(color, hardest),
          greaterThanOrEqualTo(4.5),
          reason: '$name sur le fond clair',
        );

        expect(
          _contrast(color, AppTheme.card),
          greaterThanOrEqualTo(4.5),
          reason: '$name sur carte blanche',
        );
      });
    });

    test('les couleurs d’état tiennent le 4,5:1 en mode sombre', () {
      AppTheme.applyBrightness(Brightness.dark);
      const Color hardest = AppTheme.cardDark;

      final Map<String, Color> colors = <String, Color>{
        'chlorine': AppTheme.chlorine,
        'inRange': AppTheme.inRange,
        'drift': AppTheme.drift,
        'acid': AppTheme.acid,
        'unmeasured': AppTheme.unmeasured,
        'inkMuted': AppTheme.inkMuted,
      };

      colors.forEach((String name, Color color) {
        expect(
          _contrast(color, hardest),
          greaterThanOrEqualTo(4.5),
          reason: '$name sur carte sombre',
        );
      });

      AppTheme.applyBrightness(Brightness.light);
    });

    test('le texte courant est très au-dessus du minimum', () {
      AppTheme.applyBrightness(Brightness.light);

      expect(
        _contrast(AppTheme.ink, AppTheme.surface),
        greaterThanOrEqualTo(7.0),
      );
      expect(
        _contrast(AppTheme.inkDark, AppTheme.cardDark),
        greaterThanOrEqualTo(7.0),
      );
    });

    test('le blanc sur les boutons pleins reste lisible', () {
      AppTheme.applyBrightness(Brightness.light);
      expect(
        _contrast(const Color(0xFFFFFFFF), AppTheme.chlorine),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('chaque thème redéfinit ses couleurs d’état', () {

      AppTheme.applyBrightness(Brightness.light);
      final Color lightAccent = AppTheme.chlorine;
      AppTheme.applyBrightness(Brightness.dark);
      expect(AppTheme.chlorine, isNot(lightAccent));
      AppTheme.applyBrightness(Brightness.light);
    });
  });

  group('annonces aux lecteurs d’écran', () {
    Widget wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SizedBox(width: 340, child: child)),
    );

    testWidgets('l’échelle de mesure énonce valeur, état et plage', (
      WidgetTester tester,
    ) async {

      await tester.pumpWidget(
        wrap(const MeasureScale(parameter: WaterParameter.ph, value: 7.9)),
      );

      final SemanticsNode node = tester.getSemantics(find.byType(MeasureScale));
      expect(node.label, contains('pH : 7,9'));
      expect(node.label, contains('trop haut'));
      expect(node.label, contains('Plage conseillée de 7,0 à 7,4'));
    });

    testWidgets('une échelle sans mesure le dit', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(const MeasureScale(parameter: WaterParameter.tac, value: null)),
      );

      final SemanticsNode node = tester.getSemantics(find.byType(MeasureScale));
      expect(node.label, contains('TAC non mesuré'));
      expect(node.label, contains('80 à 120'));
    });

    testWidgets('l’unité est annoncée avec la valeur', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const MeasureScale(parameter: WaterParameter.tac, value: 60)),
      );
      expect(
        tester.getSemantics(find.byType(MeasureScale)).label,
        contains('60 mg/L'),
      );
    });

    testWidgets('la ligne de mesure forme une seule annonce', (
      WidgetTester tester,
    ) async {

      await tester.pumpWidget(
        wrap(const ReadingRow(parameter: WaterParameter.tac, value: 60)),
      );

      final SemanticsNode node = tester.getSemantics(find.byType(ReadingRow));
      expect(node.label, contains('TAC'));
      expect(node.label, contains('60'));
    });

    testWidgets('une ligne actionnable est annoncée comme un bouton', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ReadingRow(parameter: WaterParameter.tac, value: 60, onTap: () {}),
        ),
      );
      final SemanticsNode node = tester.getSemantics(find.byType(ReadingRow));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(node.label, isNotEmpty);
    });
  });

  group('cibles tactiles', () {
    testWidgets('l’action d’une section fait au moins 44 px', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SectionHeader(
              label: 'À tester à la bandelette',
              action: 'Saisir',
              onAction: () {},
            ),
          ),
        ),
      );

      final Size size = tester.getSize(find.byType(TextButton));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    });

    test('le jeton de cible tactile dépasse le minimum des plateformes', () {

      expect(AppTheme.touchTarget, greaterThanOrEqualTo(48));
    });
  });

  group('mouvement réduit', () {
    testWidgets('le repère de l’échelle ne glisse pas quand c’est demandé', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: SizedBox(
                width: 340,
                child: MeasureScale(parameter: WaterParameter.ph, value: 7.2),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final AnimatedPositioned positioned = tester
          .widgetList<AnimatedPositioned>(find.byType(AnimatedPositioned))
          .first;
      expect(positioned.duration, Duration.zero);
    });
  });
}
