import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/ui/widgets/hold_button.dart';

void main() {
  late List<String> events;

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  Widget button({bool enabled = true, String? explanation}) {
    return HoldButton(
      label: 'Ouvrir',
      icon: Icons.arrow_upward,
      enabled: enabled,
      disabledExplanation: explanation,
      onPressStart: () => events.add('start'),
      onPressEnd: () => events.add('end'),
    );
  }

  setUp(() {
    events = <String>[];
  });

  group('règle n° 1 : le mouvement suit le doigt', () {
    testWidgets('le doigt posé démarre, le doigt relevé arrête', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(button()));

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldButton)),
      );
      await tester.pump();
      expect(events, <String>['start']);

      await gesture.up();
      await tester.pump();
      expect(events, <String>['start', 'end']);
    });

    testWidgets('un geste annulé par le système arrête aussi', (
      WidgetTester tester,
    ) async {

      await tester.pumpWidget(wrap(button()));

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldButton)),
      );
      await tester.pump();
      expect(events, <String>['start']);

      await gesture.cancel();
      await tester.pump();
      expect(events, <String>['start', 'end']);
    });

    testWidgets('un doigt qui glisse hors du bouton arrête', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(button()));

      final Offset center = tester.getCenter(find.byType(HoldButton));
      final TestGesture gesture = await tester.startGesture(center);
      await tester.pump();

      await gesture.moveTo(center + const Offset(0, 400));
      await tester.pump();
      expect(events, <String>['start', 'end']);

      await gesture.up();
      await tester.pump();
      expect(events, <String>['start', 'end']);
    });

    testWidgets('un mouvement à l’intérieur du bouton ne l’arrête pas', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(button()));

      final Offset center = tester.getCenter(find.byType(HoldButton));
      final TestGesture gesture = await tester.startGesture(center);
      await tester.pump();

      await gesture.moveTo(center + const Offset(4, 4));
      await tester.pump();
      expect(events, <String>['start']);

      await gesture.up();
      await tester.pump();
      expect(events, <String>['start', 'end']);
    });

    testWidgets('le widget détruit sous le doigt arrête le mouvement', (
      WidgetTester tester,
    ) async {

      await tester.pumpWidget(wrap(button()));
      await tester.startGesture(tester.getCenter(find.byType(HoldButton)));
      await tester.pump();
      expect(events, <String>['start']);

      await tester.pumpWidget(wrap(const SizedBox.shrink()));
      expect(events, <String>['start', 'end']);
    });

    testWidgets('deux appuis successifs donnent deux cycles complets', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(button()));
      final Offset center = tester.getCenter(find.byType(HoldButton));

      for (int i = 0; i < 2; i++) {
        final TestGesture gesture = await tester.startGesture(center);
        await tester.pump();
        await gesture.up();
        await tester.pump();
      }

      expect(events, <String>['start', 'end', 'start', 'end']);
    });

    testWidgets('un second doigt ne redéclenche pas le démarrage', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(button()));
      final Offset center = tester.getCenter(find.byType(HoldButton));

      final TestGesture first = await tester.startGesture(center);
      await tester.pump();
      final TestGesture second = await tester.startGesture(
        center + const Offset(2, 2),
      );
      await tester.pump();

      expect(events, <String>['start']);

      await second.up();
      await tester.pump();
      await first.up();
      await tester.pump();
      expect(events, <String>['start', 'end']);
    });
  });

  group('bouton inactif', () {
    testWidgets('aucun rappel n’est émis sans consentement', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          button(
            enabled: false,
            explanation: 'Acceptez l’avertissement de sécurité.',
          ),
        ),
      );

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldButton)),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(events, isEmpty);
    });

    testWidgets('l’explication du blocage est affichée', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          button(
            enabled: false,
            explanation: 'Acceptez l’avertissement de sécurité.',
          ),
        ),
      );

      expect(
        find.text('Acceptez l’avertissement de sécurité.'),
        findsOneWidget,
      );
    });
  });

  group('accessibilité et lisibilité', () {
    testWidgets('le libellé et l’aide sont annoncés', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(button()));

      final Semantics semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(HoldButton),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.label, 'Ouvrir');
      expect(semantics.properties.hint, contains('Maintenez'));
      expect(semantics.properties.button, isTrue);
    });

    testWidgets('la cible tactile est large', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(button()));

      expect(
        tester.getSize(find.byType(HoldButton)).height,
        greaterThanOrEqualTo(88.0),
      );
    });
  });

  group('garde-fou de source', () {
    test('le bouton n’utilise ni onTap ni GestureDetector', () {

      final String source = File('lib/ui/widgets/hold_button.dart')
          .readAsLinesSync()
          .where((String line) => !line.trimLeft().startsWith('//'))
          .join('\n');

      for (final String forbidden in <String>[
        'onTap',
        'GestureDetector',
        'InkWell',
        'ElevatedButton',
        'onLongPress',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: 'hold_button.dart contient « $forbidden »',
        );
      }

      for (final String required in <String>[
        'Listener(',
        'onPointerDown',
        'onPointerUp',
        'onPointerCancel',
      ]) {
        expect(source, contains(required), reason: required);
      }
    });
  });
}
