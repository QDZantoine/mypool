import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/models/chemical_product.dart';

void main() {
  group('produits par défaut (annexe À.3)', () {
    test('chaque rôle à un produit par défaut', () {
      for (final ChemicalRole role in ChemicalRole.values) {
        final ChemicalProduct product = ChemicalInventory.defaultFor(role);
        expect(product.role, role);
        expect(product.label, isNotEmpty);
        expect(product.activeSubstance, isNotEmpty);
      }
    });

    test('les concentrations du commerce', () {
      // Galets de trichloroisocyanurique : 90 % de chlore actif.
      expect(
        ChemicalInventory.defaultFor(ChemicalRole.chlorineSlow).activePercent,
        90.0,
      );
      // Hypochlorite de calcium (choc) : 56 %.
      expect(
        ChemicalInventory.defaultFor(ChemicalRole.chlorineShock).activePercent,
        56.0,
      );
      // Hypochlorite de sodium (liquide) : 9,6 %.
      expect(
        ChemicalInventory.defaultFor(ChemicalRole.chlorineLiquid).activePercent,
        9.6,
      );
    });

    test('les correcteurs mineraux purs sont la référence à 100 %', () {
      // Ce sont eux qui donnent les coefficients de l’annexe À.
      for (final ChemicalRole role in <ChemicalRole>[
        ChemicalRole.phMinus,
        ChemicalRole.phPlus,
        ChemicalRole.alkalinityUp,
        ChemicalRole.alkalinityDown,
        ChemicalRole.stabilizer,
        ChemicalRole.hardnessUp,
        ChemicalRole.salt,
      ]) {
        expect(
          ChemicalInventory.defaultFor(role).activePercent,
          100.0,
          reason: role.name,
        );
      }
    });

    test('seul le chlore liquide se dose en millilitres', () {
      for (final ChemicalRole role in ChemicalRole.values) {
        final DoseUnit unit = ChemicalInventory.defaultFor(role).unit;
        expect(
          unit,
          role == ChemicalRole.chlorineLiquid
              ? DoseUnit.milliliter
              : DoseUnit.gram,
          reason: role.name,
        );
      }
    });
  });

  group('fraction active', () {
    test('conversion directe du pourcentage', () {
      // 90 % -> 0,90
      expect(
        ChemicalInventory.defaultFor(ChemicalRole.chlorineSlow).activeFraction,
        closeTo(0.90, 1e-9),
      );
      // 9,6 % -> 0,096
      expect(
        ChemicalInventory.defaultFor(ChemicalRole.chlorineLiquid)
            .activeFraction,
        closeTo(0.096, 1e-9),
      );
    });

    test('bornée entre 1 % et 100 %', () {
      final ChemicalProduct base = ChemicalInventory.defaultFor(
        ChemicalRole.chlorineSlow,
      );
      // Une concentration nulle ferait diverger la dose vers l’infini.
      expect(base.copyWith(activePercent: 0.0).activeFraction, 0.01);
      expect(base.copyWith(activePercent: -50.0).activeFraction, 0.01);
      expect(base.copyWith(activePercent: 250.0).activeFraction, 1.0);
    });
  });

  group('inventaire', () {
    test('forRole rend le produit déclaré', () {
      final ChemicalProduct mine = ChemicalInventory.defaultFor(
        ChemicalRole.chlorineSlow,
      ).copyWith(activePercent: 56.0, label: 'Mes galets');
      final ChemicalInventory inventory = ChemicalInventory.standard
          .withProduct(mine);

      expect(inventory.forRole(ChemicalRole.chlorineSlow), mine);
      // Les autres rôles ne changent pas.
      expect(
        inventory.forRole(ChemicalRole.phMinus),
        ChemicalInventory.defaultFor(ChemicalRole.phMinus),
      );
    });

    test('un rôle absent retombe sur le défaut', () {
      const ChemicalInventory empty = ChemicalInventory(
        products: <ChemicalRole, ChemicalProduct>{},
      );
      expect(
        empty.forRole(ChemicalRole.phMinus),
        ChemicalInventory.defaultFor(ChemicalRole.phMinus),
      );
    });

    test('copyWith sans argument rend un inventaire égal', () {
      expect(ChemicalInventory.standard.copyWith(), ChemicalInventory.standard);
      expect(
        ChemicalInventory.standard.copyWith().hashCode,
        ChemicalInventory.standard.hashCode,
      );
      // Un inventaire de taille differente n’est pas egal.
      expect(
        ChemicalInventory.standard.copyWith(
          products: const <ChemicalRole, ChemicalProduct>{},
        ),
        isNot(ChemicalInventory.standard),
      );
    });

    test('copyWith d’un produit ne touche que le champ demande', () {
      final ChemicalProduct base = ChemicalInventory.defaultFor(
        ChemicalRole.chlorineSlow,
      );
      final ChemicalProduct renamed = base.copyWith(
        id: 'galets_maison',
        unit: DoseUnit.milliliter,
        role: ChemicalRole.chlorineLiquid,
        activeSubstance: 'autre',
      );
      expect(renamed.id, 'galets_maison');
      expect(renamed.unit, DoseUnit.milliliter);
      expect(renamed.role, ChemicalRole.chlorineLiquid);
      expect(renamed.activeSubstance, 'autre');
      expect(renamed.activePercent, base.activePercent);
      expect(base.copyWith(), base);
      // Un produit different n’est pas egal, et le type non plus.
      expect(renamed, isNot(base));
      expect(base == Object(), isFalse);
    });

    test('withProduct ne modifie pas l’inventaire d’origine', () {
      final ChemicalInventory original = ChemicalInventory.standard;
      final ChemicalProduct mine = ChemicalInventory.defaultFor(
        ChemicalRole.phMinus,
      ).copyWith(activePercent: 60.0);
      final ChemicalInventory modified = original.withProduct(mine);

      expect(modified.forRole(ChemicalRole.phMinus).activePercent, 60.0);
      expect(original.forRole(ChemicalRole.phMinus).activePercent, 100.0);
    });
  });

  group('aller-retour JSON', () {
    test('un produit survit au passage par JSON', () {
      final ChemicalProduct original = ChemicalInventory.defaultFor(
        ChemicalRole.chlorineLiquid,
      ).copyWith(activePercent: 4.8, label: 'Javel diluee');

      final ChemicalProduct restored = ChemicalProduct.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(restored, original);
    });

    test('un inventaire complet survit au passage par JSON', () {
      final ChemicalInventory original = ChemicalInventory.standard
          .withProduct(
            ChemicalInventory.defaultFor(ChemicalRole.phMinus)
                .copyWith(activePercent: 60.0),
          )
          .withProduct(
            ChemicalInventory.defaultFor(ChemicalRole.salt)
                .copyWith(label: 'Sel en sacs de 25 kg'),
          );

      final ChemicalInventory restored = ChemicalInventory.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(restored, original);
    });
  });

  group('JSON corrompu', () {
    test('un objet vide rend un produit par défaut cohérent', () {
      final ChemicalProduct restored = ChemicalProduct.fromJson(
        <String, dynamic>{},
      );
      // Le rôle par défaut est le chlore d’entretien.
      expect(restored, ChemicalInventory.defaultFor(ChemicalRole.chlorineSlow));
    });

    test('null, une chaîne ou une liste rendent le produit par défaut', () {
      final ChemicalProduct expected = ChemicalInventory.defaultFor(
        ChemicalRole.chlorineSlow,
      );
      expect(ChemicalProduct.fromJson(null), expected);
      expect(ChemicalProduct.fromJson('perdu'), expected);
      expect(ChemicalProduct.fromJson(<int>[1]), expected);
    });

    test('un rôle inconnu retombe sur le chlore d’entretien', () {
      final ChemicalProduct restored = ChemicalProduct.fromJson(
        <String, dynamic>{'role': 'poudre_de_perlimpinpin', 'label': 'Mystere'},
      );
      expect(restored.role, ChemicalRole.chlorineSlow);
      // Le libellé lisible est conserve, lui.
      expect(restored.label, 'Mystere');
      // La concentration retombe sur celle du défaut du rôle.
      expect(restored.activePercent, 90.0);
    });

    test('une concentration illisible retombe sur celle du défaut', () {
      final ChemicalProduct restored = ChemicalProduct.fromJson(
        <String, dynamic>{'role': 'phMinus', 'activePercent': 'fort'},
      );
      expect(restored.activePercent, 100.0);
    });

    test('une concentration aberrante est bornée', () {
      expect(
        ChemicalProduct.fromJson(<String, dynamic>{
          'role': 'phMinus',
          'activePercent': 0.0,
        }).activePercent,
        1.0,
      );
      expect(
        ChemicalProduct.fromJson(<String, dynamic>{
          'role': 'phMinus',
          'activePercent': 500.0,
        }).activePercent,
        100.0,
      );
    });

    test('un libellé vide est traite comme absent', () {
      final ChemicalProduct restored = ChemicalProduct.fromJson(
        <String, dynamic>{'role': 'phMinus', 'label': '   '},
      );
      expect(
        restored.label,
        ChemicalInventory.defaultFor(ChemicalRole.phMinus).label,
      );
    });

    test('un inventaire vide ou corrompu est complète par les défauts', () {
      // Un inventaire partiel doit rester exploitable par le moteur de dosage.
      final ChemicalInventory restored = ChemicalInventory.fromJson(
        <String, dynamic>{
          'products': <Object?>[
            <String, dynamic>{'role': 'phMinus', 'activePercent': 60.0},
            'ceci n’est pas un produit',
            null,
            42,
          ],
        },
      );

      expect(restored.forRole(ChemicalRole.phMinus).activePercent, 60.0);
      for (final ChemicalRole role in ChemicalRole.values) {
        expect(restored.products[role], isNotNull, reason: role.name);
      }
    });

    test('un inventaire null rend l’inventaire standard', () {
      expect(ChemicalInventory.fromJson(null), ChemicalInventory.standard);
      expect(ChemicalInventory.fromJson('perdu'), ChemicalInventory.standard);
    });
  });
}
