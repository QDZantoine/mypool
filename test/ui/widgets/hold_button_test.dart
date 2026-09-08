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
      // C'est le cas qui compte le plus : appel entrant, verrouillage de
      // l'écran, notification plein écran. Le doigt n'est jamais « relevé »,
      // le geste est annulé.
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

      // Comme sur un bouton physique dont on retire la main.
      await gesture.moveTo(center + const Offset(0, 400));
      await tester.pump();
      expect(events, <String>['start', 'end']);

      // Le relâchement qui suit ne redéclenche pas un second arrêt.
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

      // Un doigt qui tremble légèrement doit continuer à commander.
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
      // Changement d'écran, rotation, fermeture de l'application alors qu'un
      // doigt est posé.
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

      // Une paume posée à plat ne doit pas doubler les commandes.
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

      // Un bouton grisé sans explication laisse l'utilisateur chercher.
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
      // Une main mouillée sur un écran chaud rate une petite cible.
      expect(
        tester.getSize(find.byType(HoldButton)).height,
        greaterThanOrEqualTo(88.0),
      );
    });
  });

  group('garde-fou de source', () {
    test('le bouton n’utilise ni onTap ni GestureDetector', () {
      // Un appui bref déclencherait un mouvement qui se poursuivrait après le
      // relâchement, ce que la norme interdit. Et GestureDetector perd le
      // relâchement quand un ancêtre défilable gagne l'arène de gestes.
      // Les commentaires sont écartés : ce fichier CITE `onTap` et
      // `GestureDetector` pour expliquer pourquoi ils sont interdits, et un
      // garde-fou qui échoue sur sa propre justification serait inutilisable.
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
      // Et il utilise bien les quatre événements de pointeur brut.
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
