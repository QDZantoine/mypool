import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/domain/filtration_planner.dart';
import 'package:mypool/models/filtration_schedule.dart';
import 'package:mypool/models/pool_config.dart';
import 'package:mypool/ui/theme.dart';
import 'package:mypool/ui/widgets/day_timeline.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: SizedBox(width: 340, child: child)),
  );

  group('bande de journée', () {
    testWidgets('elle gradue la journée en quatre repères', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const DayTimeline(cycles: <FiltrationCycle>[])),
      );

      // Quatre repères et la borne de fin : un axe complet serait illisible
      // sur un téléphone au soleil.
      for (final String label in <String>['0h', '6h', '12h', '18h', '24h']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('elle dessine les créneaux du planning', (
      WidgetTester tester,
    ) async {
      final FiltrationSchedule plan = FiltrationPlanner.plan(
        config: const PoolConfig(),
        temperatureC: 26.0,
      );
      expect(plan.cycles.length, 3);

      await tester.pumpWidget(wrap(DayTimeline(cycles: plan.cycles)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('un créneau qui passe minuit est dessiné en deux morceaux', (
      WidgetTester tester,
    ) async {
      // La journée est un cycle, pas une ligne : un créneau de 23 h à 2 h
      // occupe les deux extrémités de la bande.
      await tester.pumpWidget(
        wrap(
          const DayTimeline(
            cycles: <FiltrationCycle>[
              FiltrationCycle(startMinuteOfDay: 1380, durationMinutes: 180),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Le fond, les trois repères internes et les deux morceaux.
      expect(find.byType(DecoratedBox), findsNWidgets(3));
    });

    testWidgets('un créneau très court reste visible', (
      WidgetTester tester,
    ) async {
      // 5 minutes sur 1 440 font moins d'un pixel : sans largeur plancher, le
      // créneau disparaîtrait de la bande.
      await tester.pumpWidget(
        wrap(
          const DayTimeline(
            cycles: <FiltrationCycle>[
              FiltrationCycle(startMinuteOfDay: 600, durationMinutes: 5),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Iterable<Positioned> slices = tester
          .widgetList<Positioned>(find.byType(Positioned))
          .where((Positioned p) => p.width != null);
      expect(slices, isNotEmpty);
      expect(slices.first.width, greaterThanOrEqualTo(3.0));
    });

    testWidgets('elle s’annonce aux lecteurs d’écran', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const DayTimeline(
            cycles: <FiltrationCycle>[
              FiltrationCycle(startMinuteOfDay: 645, durationMinutes: 390),
            ],
          ),
        ),
      );

      // Une bande dessinée est invisible au lecteur d'écran : les horaires
      // doivent être énoncés.
      final SemanticsNode node = tester.getSemantics(find.byType(DayTimeline));
      expect(node.label, contains('10:45'));
      expect(node.label, contains('17:15'));
    });

    testWidgets('sans créneau, elle le dit', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(const DayTimeline(cycles: <FiltrationCycle>[])),
      );
      expect(
        tester.getSemantics(find.byType(DayTimeline)).label,
        contains('Aucun créneau'),
      );
    });
  });
}
