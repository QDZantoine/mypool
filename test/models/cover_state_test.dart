import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/models/cover_state.dart';

final DateTime _fixedDate = DateTime.utc(2026, 7, 15, 18, 45);

void main() {
  group('état par défaut', () {
    test('on ne sait rien avant d’avoir interroge le module', () {
      const CoverState state = CoverState();

      expect(state.position, CoverPosition.unknown);
      expect(state.motion, CoverMotion.idle);
      expect(state.pump, PumpState.unknown);

      expect(state.isEstimated, isTrue);
      expect(state.isMoving, isFalse);
      expect(state.isPumpRunning, isFalse);
      expect(CoverState.unknownState, state);
    });
  });

  group('position déduite du taux d’ouverture', () {
    test('les extremites tolerent 2 % d’imprecision', () {

      expect(CoverState.positionFromRatio(0.0), CoverPosition.closed);
      expect(CoverState.positionFromRatio(0.02), CoverPosition.closed);
      expect(CoverState.positionFromRatio(0.98), CoverPosition.open);
      expect(CoverState.positionFromRatio(1.0), CoverPosition.open);
    });

    test('entre les deux, le volet est partiellement ouvert', () {
      expect(CoverState.positionFromRatio(0.03), CoverPosition.partiallyOpen);
      expect(CoverState.positionFromRatio(0.5), CoverPosition.partiallyOpen);
      expect(CoverState.positionFromRatio(0.97), CoverPosition.partiallyOpen);
    });
  });

  group('affichage', () {
    test('taux d’ouverture en pourcentage entier', () {
      expect(const CoverState().formattedOpenRatio, '0 %');
      expect(const CoverState(openRatio: 0.455).formattedOpenRatio, '46 %');
      expect(const CoverState(openRatio: 1.0).formattedOpenRatio, '100 %');
    });
  });

  group('mouvement', () {
    test('un mouvement en cours est signale', () {
      const CoverState opening = CoverState(motion: CoverMotion.opening);
      expect(opening.isMoving, isTrue);
      const CoverState closing = CoverState(motion: CoverMotion.closing);
      expect(closing.isMoving, isTrue);
    });

    test('copyWith sans argument rend un objet égal', () {
      final CoverState state = CoverState(
        position: CoverPosition.partiallyOpen,
        openRatio: 0.5,
        lastMovedAt: _fixedDate,
        pump: PumpState.on,
        pumpPowerW: 420.0,
      );
      expect(state.copyWith(), state);
      expect(state.copyWith().hashCode, state.hashCode);
    });
  });

  group('lisibilité en journal', () {
    test('toString donne position, mouvement et taux', () {
      const CoverState state = CoverState(
        position: CoverPosition.partiallyOpen,
        motion: CoverMotion.closing,
        openRatio: 0.45,
      );
      expect(state.toString(), contains('partiallyOpen'));
      expect(state.toString(), contains('closing'));
      expect(state.toString(), contains('45 %'));
    });

    test('un autre type n’est jamais égal à un état de volet', () {
      expect(const CoverState() == Object(), isFalse);
    });
  });

  group('aller-retour JSON', () {
    test('un état complet survit au passage par JSON', () {
      final CoverState original = CoverState(
        position: CoverPosition.partiallyOpen,
        openRatio: 0.45,
        isEstimated: false,
        lastMovedAt: _fixedDate,
        pump: PumpState.on,
        pumpPowerW: 420.5,
      );

      final CoverState restored = CoverState.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(restored, original);
    });

    test('un mouvement n’est jamais restaure', () {

      const CoverState original = CoverState(
        position: CoverPosition.partiallyOpen,
        motion: CoverMotion.closing,
        openRatio: 0.5,
      );

      final CoverState restored = CoverState.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(restored.motion, CoverMotion.idle);
      expect(restored.position, CoverPosition.partiallyOpen);
    });
  });

  group('JSON corrompu', () {
    test('un objet vide rend l’état inconnu', () {
      expect(CoverState.fromJson(<String, dynamic>{}), const CoverState());
    });

    test('null, une chaîne ou une liste rendent l’état inconnu', () {
      expect(CoverState.fromJson(null), const CoverState());
      expect(CoverState.fromJson('perdu'), const CoverState());
      expect(CoverState.fromJson(<int>[1]), const CoverState());
    });

    test('un taux d’ouverture hors bornes est borne', () {
      expect(
        CoverState.fromJson(<String, dynamic>{'openRatio': 2.5}).openRatio,
        1.0,
      );
      expect(
        CoverState.fromJson(<String, dynamic>{'openRatio': -1.0}).openRatio,
        0.0,
      );
      expect(
        CoverState.fromJson(<String, dynamic>{'openRatio': 'grand'}).openRatio,
        0.0,
      );
    });

    test('une position inconnue reste inconnue', () {
      expect(
        CoverState.fromJson(<String, dynamic>{'position': 'entrouvert'})
            .position,
        CoverPosition.unknown,
      );
    });

    test('une position mesurée ne se devine pas', () {

      expect(
        CoverState.fromJson(<String, dynamic>{'isEstimated': 'non'})
            .isEstimated,
        isTrue,
      );
      expect(
        CoverState.fromJson(<String, dynamic>{'isEstimated': false})
            .isEstimated,
        isFalse,
      );
    });

    test('une date de dernier mouvement illisible devient absente', () {
      expect(
        CoverState.fromJson(<String, dynamic>{'lastMovedAt': 'tantot'})
            .lastMovedAt,
        isNull,
      );
    });

    test('un état de pompe inconnu reste inconnu', () {
      expect(
        CoverState.fromJson(<String, dynamic>{'pump': 'peut-etre'}).pump,
        PumpState.unknown,
      );
      expect(
        CoverState.fromJson(<String, dynamic>{'pump': 'on'}).pump,
        PumpState.on,
      );
    });
  });
}
