import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/domain/chemistry_engine.dart';
import 'package:mypool/models/chemical_product.dart';
import 'package:mypool/models/dose_recommendation.dart';
import 'package:mypool/models/pool_config.dart';
import 'package:mypool/models/water_reading.dart';

/// Date fixe : le domaine ne lit jamais l'horloge, les tests non plus.
final DateTime _fixedDate = DateTime.utc(2026, 7, 15, 10);

WaterReading _reading({
  double? ph,
  double? freeChlorine,
  double? combinedChlorine,
  double? tac,
  double? th,
  double? stabilizer,
  double? salt,
  double? temperature,
}) {
  return WaterReading(
    takenAt: _fixedDate,
    ph: ph,
    freeChlorine: freeChlorine,
    combinedChlorine: combinedChlorine,
    tac: tac,
    th: th,
    stabilizer: stabilizer,
    salt: salt,
    temperature: temperature,
  );
}

void main() {
  /// Piscine de référence de l'annexe À : 40 m3, chlore stabilisé, produits
  /// par défaut.
  const PoolConfig pool = PoolConfig();

  group('annexe À.2 - correction de pH', () {
    test('pH 7,8 -> 7,2 dans 40 m3 à TAC 100 = 1 440 g en 2 apports', () {
      final DoseRecommendation? action = ChemistryEngine.phCorrection(
        config: pool,
        ph: 7.8,
        tacMgL: 100.0,
        sequenceIndex: 0,
      );

      expect(action, isNotNull);
      // écart 7,8 - 7,2 = 0,60 (arrondi au centieme)
      // 0,60 x 40 m3 x 60 g/m3/unité x (100 / 100) = 1 440 g de matière active
      // pH moins déclaré à 100 % -> 1 440 / 1,00 = 1 440 g de produit
      expect(action!.quantity, closeTo(1440.0, 0.001));
      // 1 440 g >= 1 000 g -> bascule en kg, deux décimales, virgule décimale
      expect(action.formattedQuantity, '1,44 kg');
      // ceil(0,60 / 0,30) = 2 apports
      expect(action.splitCount, 2);
      // 1 440 / 2 = 720 g par apport
      expect(action.quantityPerDose, closeTo(720.0, 0.001));
      expect(action.formattedQuantityPerDose, '720 g');
      expect(action.product?.role, ChemicalRole.phMinus);
      expect(action.priority, ActionPriority.ph);
      // Un apport fractionne porte toujours son avertissement.
      expect(action.warning, isNotNull);
    });

    test('doubler le TAC double la dose de pH', () {
      final DoseRecommendation? atTac100 = ChemistryEngine.phCorrection(
        config: pool,
        ph: 7.8,
        tacMgL: 100.0,
        sequenceIndex: 0,
      );
      final DoseRecommendation? atTac200 = ChemistryEngine.phCorrection(
        config: pool,
        ph: 7.8,
        tacMgL: 200.0,
        sequenceIndex: 0,
      );

      // 0,60 x 40 x 60 x (200 / 100) = 2 880 g, soit exactement le double :
      // le TAC est le pouvoir tampon, c'est lui qui résiste au changement.
      expect(atTac200!.quantity, closeTo(2880.0, 0.001));
      expect(atTac200.quantity, closeTo(atTac100!.quantity * 2, 0.001));
      // Le fractionnement ne dépend que de l'ecart de pH, pas de la quantité.
      expect(atTac200.splitCount, atTac100.splitCount);
    });

    test('sans mesure de TAC, le TAC de référence 100 est suppose', () {
      final DoseRecommendation? action = ChemistryEngine.phCorrection(
        config: pool,
        ph: 7.8,
        tacMgL: null,
        sequenceIndex: 0,
      );

      // 0,60 x 40 x 60 x (100 / 100) = 1 440 g
      expect(action!.quantity, closeTo(1440.0, 0.001));
    });

    test('écart de pH sous 0,1 -> aucune action', () {
      // 7,25 - 7,20 = 0,05 < 0,10 : dans l'incertitude du testeur.
      expect(
        ChemistryEngine.phCorrection(
          config: pool,
          ph: 7.25,
          tacMgL: 100.0,
          sequenceIndex: 0,
        ),
        isNull,
      );
      // 7,15 - 7,20 = -0,05, même conclusion dans l'autre sens.
      expect(
        ChemistryEngine.phCorrection(
          config: pool,
          ph: 7.15,
          tacMgL: 100.0,
          sequenceIndex: 0,
        ),
        isNull,
      );
    });

    test('un pH dans la plage idéale ne se corrige pas', () {
      // 7,4 - 7,2 = 0,20 : l'ecart dépasse 0,10, mais 7,4 est un bon pH.
      expect(WaterParameter.ph.statusOf(7.4), ParameterStatus.ideal);
      expect(
        ChemistryEngine.phCorrection(
          config: pool,
          ph: 7.4,
          tacMgL: 100.0,
          sequenceIndex: 0,
        ),
        isNull,
      );
    });

    test('pH trop bas -> pH plus', () {
      final DoseRecommendation? action = ChemistryEngine.phCorrection(
        config: pool,
        ph: 6.6,
        tacMgL: 100.0,
        sequenceIndex: 0,
      );

      // écart |6,6 - 7,2| = 0,60 après arrondi au centieme
      // 0,60 x 40 x 60 x 1,00 = 1 440 g de carbonate de sodium à 100 %
      expect(action!.quantity, closeTo(1440.0, 0.001));
      expect(action.product?.role, ChemicalRole.phPlus);
    });

    test('la dose suit la concentration du produit déclaré', () {
      // Même besoin : 1 440 g de matière active. Un pH moins à 60 % oblige à
      // verser davantage de produit pour le même effet dans l'eau.
      final ChemicalInventory inventory = ChemicalInventory.standard
          .withProduct(
            ChemicalInventory.defaultFor(ChemicalRole.phMinus)
                .copyWith(activePercent: 60.0),
          );
      final DoseRecommendation? action = ChemistryEngine.phCorrection(
        config: pool.copyWith(inventory: inventory),
        ph: 7.8,
        tacMgL: 100.0,
        sequenceIndex: 0,
      );

      // 1 440 g d'actif / 0,60 = 2 400 g de produit
      expect(action!.quantity, closeTo(2400.0, 0.001));
      expect(action.formattedQuantity, '2,4 kg');
    });
  });

  group('piège de virgule flottante de l’annexe À.2', () {
    test('l’écart de pH est arrondi au centieme avant tout calcul', () {
      // En Dart, 6.6 - 7.2 vaut -0.6000000000000005 et non -0,6.
      expect(6.6 - 7.2, isNot(-0.6));
      expect(ChemistryEngine.roundGap(6.6 - 7.2), -0.6);
      expect(ChemistryEngine.roundGap(7.8 - 7.2), 0.6);
    });

    test('sans arrondi, le nombre d’apports passerait de 2 à 3', () {
      final double raw = (6.6 - 7.2).abs(); // 0.6000000000000005
      // Le calcul naif : ceil(0.6000000000000005 / 0,30) = 3
      expect((raw / ChemistryEngine.maxPhStepPerDose).ceil(), 3);
      // Le calcul du moteur, arrondi puis marge epsilon : 2
      expect(
        ChemistryEngine.splitCount(
          ChemistryEngine.roundGap(raw),
          ChemistryEngine.maxPhStepPerDose,
        ),
        2,
      );
      // Et le moteur complet retient bien 2 apports.
      final DoseRecommendation? action = ChemistryEngine.phCorrection(
        config: pool,
        ph: 6.6,
        tacMgL: 100.0,
        sequenceIndex: 0,
      );
      expect(action!.splitCount, 2);
    });

    test('la marge epsilon protège les ceil() exacts', () {
      // 1,2 / 0,3 vaut exactement 4,0 : sans marge un résidu binaire donnerait
      // 5 apports. Cas réel : 8,4 - 7,2 = 1.2000000000000002.
      expect(((8.4 - 7.2) / ChemistryEngine.maxPhStepPerDose).ceil(), 5);
      final DoseRecommendation? action = ChemistryEngine.phCorrection(
        config: pool,
        ph: 8.4,
        tacMgL: 100.0,
        sequenceIndex: 0,
      );
      // ceil(1,20 / 0,30) = 4 apports
      expect(action!.splitCount, 4);
      // 1,20 x 40 x 60 x 1,00 = 2 880 g
      expect(action.quantity, closeTo(2880.0, 0.001));
    });

    test('splitCount rend au moins un apport', () {
      expect(ChemistryEngine.splitCount(0.0, 0.3), 1);
      expect(ChemistryEngine.splitCount(0.1, 0.0), 1);
      expect(ChemistryEngine.splitCount(-1.0, 0.3), 1);
    });
  });

  group('annexe À.4 - correction de TAC', () {
    test('TAC 50 -> 80 dans 40 m3 = 2 160 g en 2 apports', () {
      final DoseRecommendation? action = ChemistryEngine.alkalinityCorrection(
        config: pool,
        tacMgL: 50.0,
        sequenceIndex: 0,
      );

      expect(action, isNotNull);
      // Cible = bord bas de la plage idéale = 80 mg/L
      expect(action!.targetValue, 80.0);
      // écart 80 - 50 = 30 mg/L
      // 30 x 40 m3 x 1,8 g/m3/mg/L = 2 160 g de bicarbonate à 100 %
      expect(action.quantity, closeTo(2160.0, 0.001));
      expect(action.formattedQuantity, '2,16 kg');
      // ceil(30 / 20) = 2 apports
      expect(action.splitCount, 2);
      expect(action.product?.role, ChemicalRole.alkalinityUp);
      expect(action.priority, ActionPriority.alkalinity);
    });

    test('un TAC dans la plage idéale ne se corrige pas', () {
      expect(
        ChemistryEngine.alkalinityCorrection(
          config: pool,
          tacMgL: 100.0,
          sequenceIndex: 0,
        ),
        isNull,
      );
    });

    test('TAC trop haut : dose d’acide et avertissement de chute de pH', () {
      final DoseRecommendation? action = ChemistryEngine.alkalinityCorrection(
        config: pool,
        tacMgL: 160.0,
        sequenceIndex: 0,
      );

      // Cible = bord haut de la plage idéale = 120 mg/L, écart 40 mg/L
      // 40 x 40 x 1,5 = 2 400 g d’acide à 100 %
      expect(action!.quantity, closeTo(2400.0, 0.001));
      // ceil(40 / 20) = 2 apports
      expect(action.splitCount, 2);
      expect(action.product?.role, ChemicalRole.alkalinityDown);
      expect(action.warning, contains('pH'));
    });
  });

  group('annexe À.3 - chlore libre', () {
    test('cible = 7,5 % du stabilisant', () {
      // 40 x 0,075 = 3,0 mg/L
      expect(ChemistryEngine.targetFreeChlorine(40.0), closeTo(3.0, 1e-9));
      // 30 x 0,075 = 2,25 mg/L
      expect(ChemistryEngine.targetFreeChlorine(30.0), closeTo(2.25, 1e-9));
    });

    test('cible plafonnee à 4 mg/L', () {
      // 80 x 0,075 = 6,0 mg/L -> ramené à 4,0 : au-delà le bassin n’est plus
      // baignable, la reponse est le renouvellement d’eau.
      expect(ChemistryEngine.targetFreeChlorine(80.0), 4.0);
      // 200 x 0,075 = 15,0 -> 4,0
      expect(ChemistryEngine.targetFreeChlorine(200.0), 4.0);
    });

    test('cible avec plancher au bas de la plage idéale', () {
      // 5 x 0,075 = 0,375 mg/L, sous le minimum de 1,0 mg/L
      expect(ChemistryEngine.targetFreeChlorine(5.0), 1.0);
      // Sans mesure de stabilisant, cible nominale de 1,5 mg/L
      expect(ChemistryEngine.targetFreeChlorine(null), 1.5);
    });

    test('dose de chlore selon la concentration du produit', () {
      final DoseRecommendation? action = ChemistryEngine.chlorineCorrection(
        config: pool,
        freeChlorineMgL: 0.5,
        stabilizerMgL: 40.0,
        sequenceIndex: 0,
      );

      // cible 40 x 0,075 = 3,0 mg/L, écart 3,0 - 0,5 = 2,5 mg/L
      // 2,5 x 40 m3 x 1 g/m3/mg/L = 100 g de chlore actif
      // galets à 90 % -> 100 / 0,90 = 111,11 g
      expect(action!.quantity, closeTo(111.111, 0.001));
      expect(action.formattedQuantity, '111 g');
      expect(action.product?.role, ChemicalRole.chlorineSlow);
      expect(action.priority, ActionPriority.chlorine);
    });

    test('stabilisant saturé -> chlore non stabilisé et avertissement', () {
      final DoseRecommendation? action = ChemistryEngine.chlorineCorrection(
        config: pool,
        freeChlorineMgL: 0.5,
        stabilizerMgL: 90.0,
        sequenceIndex: 0,
      );

      // cible plafonnée à 4,0 mg/L, écart 4,0 - 0,5 = 3,5 mg/L
      // 3,5 x 40 = 140 g d’actif, granulés non stabilisees à 56 %
      // 140 / 0,56 = 250 g
      expect(action!.quantity, closeTo(250.0, 0.001));
      expect(action.formattedQuantity, '250 g');
      expect(action.product?.role, ChemicalRole.chlorineShock);
      expect(action.warning, contains('NON'));
    });

    test('sans mesure de stabilisant, la cible nominale est expliquee', () {
      final DoseRecommendation? action = ChemistryEngine.chlorineCorrection(
        config: pool,
        freeChlorineMgL: 0.5,
        stabilizerMgL: null,
        sequenceIndex: 0,
      );

      // cible nominale 1,5 mg/L, écart 1,5 - 0,5 = 1,0 mg/L
      // 1,0 x 40 m3 = 40 g d’actif, galets à 90 % -> 40 / 0,90 = 44,44 g
      expect(action!.quantity, closeTo(44.444, 0.001));
      // L’explication ne peut pas parler d’un stabilisant non mesure.
      expect(action.explanation, isNot(contains('stabilisant')));
      expect(action.explanation, contains('1,5 mg/L'));
    });

    test('chlore en excès : aucun produit, seulement un conseil', () {
      final DoseRecommendation? action = ChemistryEngine.chlorineCorrection(
        config: pool,
        freeChlorineMgL: 4.5,
        stabilizerMgL: 30.0,
        sequenceIndex: 0,
      );

      // 4,5 mg/L > 3,0 mg/L acceptable : rien à verser, le chlore se consommé.
      expect(action!.quantity, 0.0);
      expect(action.product, isNull);
      expect(action.warning, contains('Baignade'));
    });

    test('chlore suffisant -> aucune action', () {
      // cible 30 x 0,075 = 2,25 ; mesure 2,3 -> écart négatif
      expect(
        ChemistryEngine.chlorineCorrection(
          config: pool,
          freeChlorineMgL: 2.3,
          stabilizerMgL: 30.0,
          sequenceIndex: 0,
        ),
        isNull,
      );
    });

    test('écart de chlore sous 0,3 mg/L -> aucune action', () {
      // cible 2,25 ; mesure 2,0 -> écart 0,25 < 0,30, sous la résolution du
      // testeur : doser 11 g de galets ne se verrait pas à la mesure suivante.
      expect(
        ChemistryEngine.chlorineCorrection(
          config: pool,
          freeChlorineMgL: 2.0,
          stabilizerMgL: 30.0,
          sequenceIndex: 0,
        ),
        isNull,
      );
      // Le même chlore de 2,0 mg/L avec un stabilisant de 80 mg/L exige en
      // revanche une correction : cible plafonnée à 4,0, écart 2,0 mg/L.
      expect(
        ChemistryEngine.chlorineCorrection(
          config: pool,
          freeChlorineMgL: 2.0,
          stabilizerMgL: 80.0,
          sequenceIndex: 0,
        ),
        isNotNull,
      );
    });

    test('bassin à l’oxygène actif : pas de chlore à doser', () {
      expect(
        ChemistryEngine.chlorineCorrection(
          config: pool.copyWith(treatment: TreatmentType.activeOxygen),
          freeChlorineMgL: 0.0,
          stabilizerMgL: 30.0,
          sequenceIndex: 0,
        ),
        isNull,
      );
    });
  });

  group('annexe À.5 - traitement choc', () {
    test('chloramines à 1,0 mg/L dans 40 m3 = choc visant 10 mg/L', () {
      final DoseRecommendation? action = ChemistryEngine.shockCorrection(
        config: pool,
        combinedChlorineMgL: 1.0,
        freeChlorineMgL: 0.0,
        sequenceIndex: 0,
      );

      expect(action, isNotNull);
      // 1,0 x 10 = 10,0 mg/L de chlore libre à atteindre
      expect(ChemistryEngine.shockTargetFreeChlorine(1.0), 10.0);
      expect(action!.targetValue, 10.0);
      // écart 10,0 - 0,0 = 10,0 mg/L -> 10,0 x 40 m3 = 400 g de chlore actif
      // granulés de choc à 56 % -> 400 / 0,56 = 714,29 g
      expect(action.quantity, closeTo(714.286, 0.001));
      expect(action.formattedQuantity, '714 g');
      expect(action.priority, ActionPriority.urgent);
      expect(action.warning, contains('Baignade interdite'));
    });

    test('le chlore libre déjà present compte dans la cible', () {
      final DoseRecommendation? action = ChemistryEngine.shockCorrection(
        config: pool,
        combinedChlorineMgL: 1.0,
        freeChlorineMgL: 2.0,
        sequenceIndex: 0,
      );

      // écart 10,0 - 2,0 = 8,0 mg/L -> 8,0 x 40 = 320 g d’actif
      // 320 / 0,56 = 571,43 g
      expect(action!.quantity, closeTo(571.429, 0.001));
    });

    test('chloramines dans la tolérance -> aucun choc', () {
      // 0,6 mg/L est la limite acceptable, elle ne declenche pas de choc.
      expect(
        ChemistryEngine.shockCorrection(
          config: pool,
          combinedChlorineMgL: 0.6,
          freeChlorineMgL: 0.0,
          sequenceIndex: 0,
        ),
        isNull,
      );
    });
  });

  group('annexe À.4 - stabilisant', () {
    test('stabilisant 80 -> 50 dans 40 m3 = 15 m3 à renouveler', () {
      // 40 x (80 - 50) / 80 = 40 x 0,375 = 15 m3
      expect(
        ChemistryEngine.waterRenewalM3(
          volumeM3: 40.0,
          current: 80.0,
          target: 50.0,
        ),
        closeTo(15.0, 1e-9),
      );

      final DoseRecommendation? action = ChemistryEngine.stabilizerCorrection(
        config: pool,
        stabilizerMgL: 80.0,
        sequenceIndex: 0,
      );

      expect(action, isNotNull);
      // Cible = bord haut de la plage idéale = 50 mg/L
      expect(action!.targetValue, 50.0);
      expect(action.quantity, closeTo(15.0, 1e-9));
      expect(action.unit, DoseUnit.cubicMeter);
      expect(action.formattedQuantity, '15 m³');
      // Un renouvellement d’eau n’est pas un dosage : aucun produit.
      expect(action.product, isNull);
      expect(action.priority, ActionPriority.balance);
    });

    test('renouvellement nul quand la cible est déjà atteinte', () {
      expect(
        ChemistryEngine.waterRenewalM3(
          volumeM3: 40.0,
          current: 40.0,
          target: 50.0,
        ),
        0.0,
      );
      // Volume nul : rien à renouveler.
      expect(
        ChemistryEngine.waterRenewalM3(
          volumeM3: 0.0,
          current: 80.0,
          target: 50.0,
        ),
        0.0,
      );
    });

    test('stabilisant trop bas -> apport d’acide cyanurique', () {
      final DoseRecommendation? action = ChemistryEngine.stabilizerCorrection(
        config: pool,
        stabilizerMgL: 5.0,
        sequenceIndex: 0,
      );

      // Cible = bord bas = 20 mg/L, écart 15 mg/L
      // 15 x 40 m3 x 1 g/m3/mg/L = 600 g à 100 %
      expect(action!.quantity, closeTo(600.0, 0.001));
      expect(action.product?.role, ChemicalRole.stabilizer);
    });

    test('stabilisant dans la plage -> aucune action', () {
      expect(
        ChemistryEngine.stabilizerCorrection(
          config: pool,
          stabilizerMgL: 30.0,
          sequenceIndex: 0,
        ),
        isNull,
      );
    });
  });

  group('TH et sel', () {
    test('TH trop bas -> durcisseur', () {
      final DoseRecommendation? action = ChemistryEngine.hardnessCorrection(
        config: pool,
        thMgL: 90.0,
        sequenceIndex: 0,
      );

      // Cible = bord bas = 100 mg/L, écart 10 mg/L
      // 10 x 40 m3 x 1,48 g/m3/mg/L = 592 g de chlorure de calcium à 100 %
      expect(action!.quantity, closeTo(592.0, 0.001));
      expect(action.product?.role, ChemicalRole.hardnessUp);
    });

    test('TH trop haut -> dilution', () {
      final DoseRecommendation? action = ChemistryEngine.hardnessCorrection(
        config: pool,
        thMgL: 400.0,
        sequenceIndex: 0,
      );

      // Cible = bord haut = 300 mg/L
      // 40 x (400 - 300) / 400 = 10 m3
      expect(action!.quantity, closeTo(10.0, 1e-9));
      expect(action.unit, DoseUnit.cubicMeter);
    });

    test('TH de 250 mg/L est dans la plage -> aucune action', () {
      expect(
        ChemistryEngine.hardnessCorrection(
          config: pool,
          thMgL: 250.0,
          sequenceIndex: 0,
        ),
        isNull,
      );
    });

    test('le sel n’est corrige que sur un bassin à électrolyse', () {
      // Chlore stabilisé : la salinité n’a pas de consigne.
      expect(
        ChemistryEngine.saltCorrection(
          config: pool,
          saltGPerL: 2.0,
          sequenceIndex: 0,
        ),
        isNull,
      );

      final DoseRecommendation? action = ChemistryEngine.saltCorrection(
        config: pool.copyWith(treatment: TreatmentType.salt),
        saltGPerL: 2.0,
        sequenceIndex: 0,
      );
      // Cible = bord bas = 3,0 g/L, écart 1,0 g/L
      // 1,0 x 40 m3 x 1 000 g/m3/(g/L) = 40 000 g de sel à 100 %
      expect(action!.quantity, closeTo(40000.0, 0.001));
      expect(action.formattedQuantity, '40 kg');
    });

    test('sel trop haut -> dilution', () {
      final DoseRecommendation? action = ChemistryEngine.saltCorrection(
        config: pool.copyWith(treatment: TreatmentType.salt),
        saltGPerL: 6.0,
        sequenceIndex: 0,
      );

      // Cible = bord haut = 5,0 g/L -> 40 x (6 - 5) / 6 = 6,67 m3
      expect(action!.quantity, closeTo(6.6667, 0.001));
    });
  });

  group('assemblage des recommandations', () {
    test('mesure vide -> aucune action', () {
      final WaterReading empty = _reading();
      expect(empty.isEmpty, isTrue);
      expect(ChemistryEngine.recommend(config: pool, reading: empty), isEmpty);
    });

    test('volume nul -> aucune action', () {
      // Sans volume, une dose n’a pas de sens : mieux vaut ne rien proposer
      // que proposer zéro gramme.
      expect(
        ChemistryEngine.recommend(
          config: pool.copyWith(volumeM3: 0.0),
          reading: _reading(ph: 7.8, tac: 50.0, freeChlorine: 0.2),
        ),
        isEmpty,
      );
    });

    test('ordre métier : choc, TAC, pH, chlore, puis équilibre', () {
      final List<DoseRecommendation> actions = ChemistryEngine.recommend(
        config: pool.copyWith(treatment: TreatmentType.salt),
        reading: _reading(
          ph: 7.9,
          freeChlorine: 0.5,
          combinedChlorine: 0.8,
          tac: 60.0,
          th: 90.0,
          stabilizer: 90.0,
          salt: 2.0,
        ),
      );

      // Le moteur produit les actions dans l’ordre de la fiche de mesure ;
      // c’est le tri explicite sur (priorité, ordre d’ajout) qui remet
      // l’ordre métier. Le TAC stabilise le pH, le pH commande le chlore.
      expect(
        actions.map((DoseRecommendation a) => a.parameter).toList(),
        <WaterParameter>[
          WaterParameter.combinedChlorine, // urgent
          WaterParameter.tac, // alkalinity
          WaterParameter.ph, // ph
          WaterParameter.freeChlorine, // chlorine
          WaterParameter.th, // balance, ajoute en premier
          WaterParameter.stabilizer, // balance
          WaterParameter.salt, // balance, ajoute en dernier
        ],
      );

      // Les rangs de priorité sont croissants du debut à la fin.
      final List<int> ranks = actions
          .map((DoseRecommendation a) => a.priority.rank)
          .toList(growable: false);
      for (int i = 1; i < ranks.length; i++) {
        expect(ranks[i], greaterThanOrEqualTo(ranks[i - 1]));
      }
    });

    test('à priorité égale, l’ordre d’ajout est respecte', () {
      // Trois actions de rang « balance » : seul l’ordre d’ajout les departage,
      // et il ne doit pas dependre de la stabilite du tri de Dart.
      final List<DoseRecommendation> unsorted = <DoseRecommendation>[
        const DoseRecommendation(
          parameter: WaterParameter.salt,
          priority: ActionPriority.balance,
          sequenceIndex: 6,
          title: 'sel',
          explanation: '',
          quantity: 1,
          unit: DoseUnit.gram,
          splitCount: 1,
        ),
        const DoseRecommendation(
          parameter: WaterParameter.th,
          priority: ActionPriority.balance,
          sequenceIndex: 4,
          title: 'th',
          explanation: '',
          quantity: 1,
          unit: DoseUnit.gram,
          splitCount: 1,
        ),
        const DoseRecommendation(
          parameter: WaterParameter.ph,
          priority: ActionPriority.ph,
          sequenceIndex: 0,
          title: 'ph',
          explanation: '',
          quantity: 1,
          unit: DoseUnit.gram,
          splitCount: 1,
        ),
        const DoseRecommendation(
          parameter: WaterParameter.stabilizer,
          priority: ActionPriority.balance,
          sequenceIndex: 5,
          title: 'stab',
          explanation: '',
          quantity: 1,
          unit: DoseUnit.gram,
          splitCount: 1,
        ),
      ];

      expect(
        DoseRecommendation.sorted(unsorted)
            .map((DoseRecommendation a) => a.title)
            .toList(),
        <String>['ph', 'th', 'stab', 'sel'],
      );
    });

    test('une eau parfaite ne produit aucune action', () {
      final List<DoseRecommendation> actions = ChemistryEngine.recommend(
        config: pool,
        reading: _reading(
          ph: 7.2,
          freeChlorine: 2.0,
          combinedChlorine: 0.1,
          tac: 100.0,
          th: 250.0,
          stabilizer: 30.0,
          temperature: 26.0,
        ),
      );

      expect(actions, isEmpty);
    });

    test('la température seule ne declenche aucun dosage', () {
      // La température ne se corrige pas : elle sert à la filtration.
      expect(
        ChemistryEngine.recommend(
          config: pool,
          reading: _reading(temperature: 26.0),
        ),
        isEmpty,
      );
    });
  });

  group('conversion matière active -> produit', () {
    test('400 g de chlore actif selon le produit déclaré', () {
      // Galets à 90 % : 400 / 0,90 = 444,44 g
      expect(
        ChemistryEngine.productQuantity(
          400.0,
          ChemicalInventory.defaultFor(ChemicalRole.chlorineSlow),
        ),
        closeTo(444.444, 0.001),
      );
      // Granulés à 56 % : 400 / 0,56 = 714,29 g
      expect(
        ChemistryEngine.productQuantity(
          400.0,
          ChemicalInventory.defaultFor(ChemicalRole.chlorineShock),
        ),
        closeTo(714.286, 0.001),
      );
      // Chlore liquide à 9,6 % : 400 / 0,096 = 4 166,67 ml
      expect(
        ChemistryEngine.productQuantity(
          400.0,
          ChemicalInventory.defaultFor(ChemicalRole.chlorineLiquid),
        ),
        closeTo(4166.667, 0.001),
      );
    });

    test('une concentration corrompue ne fait pas diverger la dose', () {
      // activeFraction est borne à 1 % : 400 / 0,01 = 40 000, une valeur
      // absurde mais finie, affichable, et non un infini.
      final ChemicalProduct broken = ChemicalInventory.defaultFor(
        ChemicalRole.chlorineSlow,
      ).copyWith(activePercent: 0.0);
      expect(
        ChemistryEngine.productQuantity(400.0, broken),
        closeTo(40000.0, 0.001),
      );
    });
  });

  group('cible de correction', () {
    test('le pH vise 7,2, les autres paramètres le bord de plage', () {
      // Le pH est l’exception : on vise l’optimum d’efficacité du chlore.
      expect(ChemistryEngine.correctionTarget(WaterParameter.ph, 7.9), 7.2);
      expect(ChemistryEngine.correctionTarget(WaterParameter.ph, 6.5), 7.2);
      // TAC 50 -> bord bas 80 ; TAC 160 -> bord haut 120
      expect(ChemistryEngine.correctionTarget(WaterParameter.tac, 50.0), 80.0);
      expect(
        ChemistryEngine.correctionTarget(WaterParameter.tac, 160.0),
        120.0,
      );
      // Une valeur déjà dans la plage est sa propre cible.
      expect(
        ChemistryEngine.correctionTarget(WaterParameter.tac, 100.0),
        100.0,
      );
    });
  });

  group('lisibilité des objets en journal', () {
    test('toString donne l’essentiel sans trace technique', () {
      final DoseRecommendation? action = ChemistryEngine.phCorrection(
        config: pool,
        ph: 7.8,
        tacMgL: 100.0,
        sequenceIndex: 0,
      );
      expect(action.toString(), contains('1,44 kg'));
      expect(pool.toString(), contains('40'));
      expect(_reading(ph: 7.8).toString(), contains('7.8'));
      expect(
        ChemicalInventory.defaultFor(ChemicalRole.chlorineSlow).toString(),
        contains('90'),
      );
      expect(ChemicalInventory.standard.toString(), contains('10'));
    });
  });
}
