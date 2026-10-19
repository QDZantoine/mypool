import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/models/chemical_product.dart';
import 'package:mypool/models/dose_recommendation.dart';
import 'package:mypool/models/water_reading.dart';

DoseRecommendation _action({
  double quantity = 100.0,
  DoseUnit unit = DoseUnit.gram,
  int splitCount = 1,
  ActionPriority priority = ActionPriority.ph,
  int sequenceIndex = 0,
}) {
  return DoseRecommendation(
    parameter: WaterParameter.ph,
    priority: priority,
    sequenceIndex: sequenceIndex,
    title: 'Baisser le pH',
    explanation: 'Le chlore est plus efficace a pH 7,2.',
    quantity: quantity,
    unit: unit,
    splitCount: splitCount,
    product: ChemicalInventory.defaultFor(ChemicalRole.phMinus),
    currentValue: 7.8,
    targetValue: 7.2,
  );
}

void main() {
  group('formatage des quantités', () {
    test('les cas de référence du cahier des charges', () {

      expect(DoseRecommendation.formatQuantity(250.0, DoseUnit.gram), '250 g');

      expect(
        DoseRecommendation.formatQuantity(1440.0, DoseUnit.gram),
        '1,44 kg',
      );

      expect(
        DoseRecommendation.formatQuantity(400.0, DoseUnit.milliliter),
        '400 ml',
      );

      expect(
        DoseRecommendation.formatQuantity(1500.0, DoseUnit.milliliter),
        '1,5 L',
      );

      expect(
        DoseRecommendation.formatQuantity(15.0, DoseUnit.cubicMeter),
        '15 m³',
      );
    });

    test('bascule exactement à 1 000', () {
      expect(DoseRecommendation.formatQuantity(999.0, DoseUnit.gram), '999 g');

      expect(DoseRecommendation.formatQuantity(1000.0, DoseUnit.gram), '1 kg');
      expect(
        DoseRecommendation.formatQuantity(1000.0, DoseUnit.milliliter),
        '1 L',
      );
    });

    test('arrondis', () {

      expect(
        DoseRecommendation.formatQuantity(111.111, DoseUnit.gram),
        '111 g',
      );

      expect(
        DoseRecommendation.formatQuantity(714.286, DoseUnit.gram),
        '714 g',
      );

      expect(
        DoseRecommendation.formatQuantity(4166.667, DoseUnit.milliliter),
        '4,17 L',
      );

      expect(
        DoseRecommendation.formatQuantity(2400.0, DoseUnit.gram),
        '2,4 kg',
      );

      expect(
        DoseRecommendation.formatQuantity(40000.0, DoseUnit.gram),
        '40 kg',
      );

      expect(
        DoseRecommendation.formatQuantity(6.6667, DoseUnit.cubicMeter),
        '6,7 m³',
      );
    });

    test('quantité nulle', () {
      expect(DoseRecommendation.formatQuantity(0.0, DoseUnit.gram), '0 g');
      expect(
        DoseRecommendation.formatQuantity(0.0, DoseUnit.cubicMeter),
        '0 m³',
      );
    });
  });

  group('fractionnement', () {
    test('sans fractionnement, l’apport unique vaut la quantité totale', () {
      final DoseRecommendation action = _action(quantity: 250.0);
      expect(action.isSplit, isFalse);
      expect(action.quantityPerDose, 250.0);
      expect(action.formattedQuantityPerDose, '250 g');
    });

    test('avec fractionnement, la quantité est divisee', () {
      final DoseRecommendation action = _action(
        quantity: 1440.0,
        splitCount: 2,
      );
      expect(action.isSplit, isTrue);

      expect(action.quantityPerDose, 720.0);
      expect(action.formattedQuantityPerDose, '720 g');
      expect(action.formattedQuantity, '1,44 kg');
    });

    test('un splitCount de 0 ou négatif ne divise pas', () {

      expect(_action(quantity: 100.0, splitCount: 0).quantityPerDose, 100.0);
      expect(_action(quantity: 100.0, splitCount: -3).quantityPerDose, 100.0);
    });
  });

  group('ordre métier', () {
    test('les rangs suivent TAC -> pH -> chlore -> équilibre', () {

      expect(
        ActionPriority.urgent.rank,
        lessThan(ActionPriority.alkalinity.rank),
      );

      expect(ActionPriority.alkalinity.rank, lessThan(ActionPriority.ph.rank));

      expect(ActionPriority.ph.rank, lessThan(ActionPriority.chlorine.rank));
      expect(
        ActionPriority.chlorine.rank,
        lessThan(ActionPriority.balance.rank),
      );
      expect(
        ActionPriority.balance.rank,
        lessThan(ActionPriority.information.rank),
      );
    });

    test('tri explicite sur (priorité, ordre d’ajout)', () {
      final List<DoseRecommendation> unsorted = <DoseRecommendation>[
        _action(priority: ActionPriority.balance, sequenceIndex: 9),
        _action(priority: ActionPriority.alkalinity, sequenceIndex: 3),
        _action(priority: ActionPriority.balance, sequenceIndex: 5),
        _action(priority: ActionPriority.urgent, sequenceIndex: 7),
      ];

      final List<DoseRecommendation> sorted = DoseRecommendation.sorted(
        unsorted,
      );

      expect(
        sorted.map((DoseRecommendation a) => a.sequenceIndex).toList(),

        <int>[7, 3, 5, 9],
      );
    });

    test('sorted ne modifie pas la liste d’origine', () {
      final List<DoseRecommendation> original = <DoseRecommendation>[
        _action(priority: ActionPriority.balance, sequenceIndex: 2),
        _action(priority: ActionPriority.urgent, sequenceIndex: 1),
      ];
      DoseRecommendation.sorted(original);
      expect(original.first.priority, ActionPriority.balance);
    });

    test('une liste vide reste vide', () {
      expect(DoseRecommendation.sorted(const <DoseRecommendation>[]), isEmpty);
    });
  });

  group('aller-retour JSON', () {
    test('une action complète survit au passage par JSON', () {
      final DoseRecommendation original = _action(
        quantity: 1440.0,
        splitCount: 2,
      ).copyWith(warning: 'À fractionner en 2 apports.');

      final DoseRecommendation restored = DoseRecommendation.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(restored, original);
    });

    test('une action sans produit survit aussi', () {
      const DoseRecommendation original = DoseRecommendation(
        parameter: WaterParameter.stabilizer,
        priority: ActionPriority.balance,
        sequenceIndex: 4,
        title: 'Renouveler une partie de l’eau',
        explanation: 'Le stabilisant ne se detruit pas.',
        quantity: 15.0,
        unit: DoseUnit.cubicMeter,
        splitCount: 1,
      );

      final DoseRecommendation restored = DoseRecommendation.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(restored, original);
      expect(restored.product, isNull);
    });

    test('copyWith sans argument rend un objet égal', () {
      final DoseRecommendation action = _action();
      expect(action.copyWith(), action);
      expect(action.copyWith().hashCode, action.hashCode);
    });
  });

  group('JSON corrompu', () {
    test('un objet vide rend une action neutre et affichable', () {
      final DoseRecommendation restored = DoseRecommendation.fromJson(
        <String, dynamic>{},
      );

      expect(restored.title, 'Action');
      expect(restored.quantity, 0.0);
      expect(restored.unit, DoseUnit.gram);
      expect(restored.splitCount, 1);
      expect(restored.priority, ActionPriority.information);
      expect(restored.product, isNull);
    });

    test('null, une chaîne ou une liste rendent une action neutre', () {
      expect(DoseRecommendation.fromJson(null).quantity, 0.0);
      expect(DoseRecommendation.fromJson('perdu').title, 'Action');
      expect(DoseRecommendation.fromJson(<int>[1]).splitCount, 1);
    });

    test('une quantité négative est ramenée à zéro', () {

      expect(
        DoseRecommendation.fromJson(<String, dynamic>{'quantity': -500.0})
            .quantity,
        0.0,
      );
    });

    test('un splitCount aberrant est borne à au moins 1', () {
      expect(
        DoseRecommendation.fromJson(<String, dynamic>{'splitCount': 0})
            .splitCount,
        1,
      );
      expect(
        DoseRecommendation.fromJson(<String, dynamic>{'splitCount': -5})
            .splitCount,
        1,
      );
      expect(
        DoseRecommendation.fromJson(<String, dynamic>{'splitCount': 9999})
            .splitCount,
        100,
      );
    });

    test('un paramètre ou une unité inconnus retombent sur les défauts', () {
      final DoseRecommendation restored = DoseRecommendation.fromJson(
        <String, dynamic>{
          'parameter': 'radioactivite',
          'unit': 'cuillere a soupe',
          'priority': 'tres urgent',
        },
      );

      expect(restored.parameter, WaterParameter.ph);
      expect(restored.unit, DoseUnit.gram);
      expect(restored.priority, ActionPriority.information);
    });

    test('un produit corrompu ne fait pas echouer l’action', () {
      final DoseRecommendation restored = DoseRecommendation.fromJson(
        <String, dynamic>{'title': 'Baisser le pH', 'product': 'perdu'},
      );

      expect(restored.product, isNotNull);
      expect(restored.title, 'Baisser le pH');
    });
  });
}
