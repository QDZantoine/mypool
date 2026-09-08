import '../models/chemical_product.dart';
import '../models/dose_recommendation.dart';
import '../models/pool_config.dart';
import '../models/water_reading.dart';

/// Moteur de dosage (annexe À.2 à À.5).
///
/// PUR : aucun import Flutter, aucun accès disque ou réseau, aucune lecture de
/// l'horloge. Tout entre par paramètre, ce qui rend chaque coefficient
/// vérifiable par un calcul à la main.
///
/// Principe commun à toutes les doses : on calcule d'abord une masse de
/// Matière ACTIVE nécessaire dans l'eau, puis on la divise par la concentration
/// du produit DÉCLARÉ par l'utilisateur. Aucune concentration n'est figée ici.
class ChemistryEngine {
  // ---------------------------------------------------------------------------
  // Coefficients (annexe À). Chacun porte son unité et son origine.
  // ---------------------------------------------------------------------------

  /// Grammes de matière active par m3 pour déplacer le pH d'UNE unité complète,
  /// au TAC de référence de 100 mg/L (annexe À.2).
  ///
  /// Cas de vérification : pH 7,8 -> 7,2 dans 40 m3 à TAC 100
  /// = 0,60 x 40 x 60 x (100 / 100) = 1 440 g.
  static const double phGramsPerM3PerUnitAtTac100 = 60.0;

  /// TAC de référence des coefficients de pH, en mg/L.
  ///
  /// La dose de correcteur de pH est proportionnelle au TAC : le TAC est le
  /// pouvoir tampon de l'eau, c'est exactement ce qui résiste au changement de
  /// pH. À TAC 200 il faut donc deux fois plus de produit qu'a TAC 100.
  static const double referenceTacMgL = 100.0;

  /// Déplacement de pH maximal par apport, en unités de pH (annexe À.2).
  ///
  /// Au-delà, l'apport crée un point de concentration acide qui attaque le
  /// liner et fausse la mesure suivante. C'est ce pas qui donne 2 apports pour
  /// un écart de 0,60.
  static const double maxPhStepPerDose = 0.30;

  /// Écart de pH en dessous duquel on ne dose pas.
  ///
  /// 0,1 unité est l'ordre de grandeur de l'incertitude d'un testeur
  /// colorimétrique : doser pour moins que cela consomme du produit sans effet
  /// mesurable.
  static const double minPhGap = 0.10;

  /// Grammes de bicarbonate de sodium pur par m3 pour +1 mg/L de TAC
  /// (annexe À.4).
  ///
  /// Cas de vérification : TAC 50 -> 80 dans 40 m3
  /// = 30 x 40 x 1,8 = 2 160 g.
  static const double tacUpGramsPerM3PerMgL = 1.8;

  /// Grammes d'acide pur par m3 pour -1 mg/L de TAC.
  ///
  /// HYPOTHÈSE : valeur usuelle des fiches produit, l'annexe À ne fournit pas
  /// de cas de vérification pour la baisse de TAC. À confirmer.
  static const double tacDownGramsPerM3PerMgL = 1.5;

  /// Variation de TAC maximale par apport, en mg/L (annexe À.4).
  ///
  /// Donne 2 apports pour un écart de 30 mg/L. Un apport unique de bicarbonate
  /// trouble l'eau et fait remonter le pH d'un coup.
  static const double maxTacStepPerDoseMgL = 20.0;

  /// Part du stabilisant qui fixe le chlore libre à viser (annexe À.3).
  ///
  /// 7,5 % : plus le stabilisant est élevé, plus il freine le chlore, et plus
  /// il faut de chlore libre pour obtenir la même désinfection.
  static const double stabilizerToChlorineRatio = 0.075;

  /// Plafond absolu du chlore libre vise, en mg/L.
  ///
  /// Au-delà le bassin n'est plus baignable. Quand la règle des 7,5 % demande
  /// davantage, la bonne reponse n'est pas plus de chlore mais un
  /// renouvellement d'eau pour faire baisser le stabilisant.
  static const double maxTargetFreeChlorineMgL = 4.0;

  /// Écart de chlore libre en dessous duquel on ne dose pas, en mg/L.
  ///
  /// 0,3 mg/L est la plus petite graduation lisible sur un testeur
  /// colorimétrique : passer de 2,0 à 2,25 mg/L n'est ni mesurable ni utile.
  static const double minChlorineGapMgL = 0.30;

  /// Facteur du traitement choc (annexe À.5).
  ///
  /// Point de rupture de la chloration : il faut environ 10 fois la teneur en
  /// chlore combiné pour casser les chloramines. En dessous, on nourrit le
  /// problème au lieu de le détruire.
  static const double shockMultiplier = 10.0;

  /// Grammes de chlorure de calcium dihydrate pur par m3 pour +1 mg/L de TH.
  ///
  /// HYPOTHÈSE : stœchiométrie CaCl2.2H2O (147 g/mol) pour un TH exprimé en
  /// équivalent CaCO3 (100 g/mol), soit 1,47. Arrondi à 1,48 pour couvrir la
  /// pureté commerciale. L'annexe À ne fournit pas de cas de vérification.
  static const double hardnessGramsPerM3PerMgL = 1.48;

  /// Grammes de matière active par m3 pour +1 mg/L d'un paramètre exprimé en
  /// mg/L. C'est une identité d'unites (1 mg/L = 1 g/m3), pas un coefficient
  /// empirique : elle vaut pour le chlore et pour le stabilisant.
  static const double gramsPerM3PerMgL = 1.0;

  /// Grammes de sel par m3 pour +1 g/L de salinité. Identité d'unites egalement
  /// (1 g/L = 1 000 g/m3).
  static const double gramsPerM3PerGPerL = 1000.0;

  /// Marge de sécurité appliquee avant chaque `ceil()` de fractionnement.
  ///
  /// Sans elle, un besoin de 2,0 apports stocke comme 2,000000000000002 en
  /// virgule flottante donnerait 3 apports.
  static const double splitEpsilon = 1e-9;

  // ---------------------------------------------------------------------------
  // Briques de calcul, publiques pour être testables une par une.
  // ---------------------------------------------------------------------------

  /// Arrondit un écart de mesure au centieme AVANT tout calcul.
  ///
  /// `7.8 - 7.2` vaut `0.6000000000000005` en virgule flottante. Sans cet
  /// arrondi, le fractionnement passe de 2 à 3 apports pour une difference
  /// invisible à l'affichage.
  static double roundGap(double gap) {
    return (gap * 100).roundToDouble() / 100;
  }

  /// Nombre d'apports nécessaires pour couvrir `need` sans dépasser
  /// `maxPerDose` à chaque fois.
  static int splitCount(double need, double maxPerDose) {
    if (maxPerDose <= 0 || need <= 0) {
      return 1;
    }
    final int count = ((need / maxPerDose) - splitEpsilon).ceil();
    return count < 1 ? 1 : count;
  }

  /// Convertit une masse de matière active en quantité de produit à verser.
  ///
  /// C'est le seul endroit ou la concentration intervient : 400 g de chlore
  /// actif font 444 g de galets à 90 %, 714 g de granulés à 56 % ou 4,17 L de
  /// chlore liquide à 9,6 %.
  static double productQuantity(double activeGrams, ChemicalProduct product) {
    return activeGrams / product.activeFraction;
  }

  /// Cible d'une correction.
  ///
  /// On ne vise pas le milieu de la plage mais son bord le plus proche : entrer
  /// dans la plage suffit, et cela consomme le minimum de produit. Le pH est
  /// l'exception, on vise 7,2 parce que c'est l'optimum d'efficacite du chlore.
  static double correctionTarget(WaterParameter parameter, double current) {
    if (parameter == WaterParameter.ph) {
      return parameter.target;
    }
    if (current < parameter.idealMin) {
      return parameter.idealMin;
    }
    if (current > parameter.idealMax) {
      return parameter.idealMax;
    }
    return current;
  }

  /// Chlore libre à viser, en mg/L (annexe À.3).
  ///
  /// Règle des 7,5 % du stabilisant, plancher au bas de la plage idéale et
  /// plafond à 4 mg/L. Sans mesure de stabilisant on vise la cible nominale.
  static double targetFreeChlorine(double? stabilizerMgL) {
    if (stabilizerMgL == null) {
      return WaterParameter.freeChlorine.target;
    }
    final double fromStabilizer = stabilizerMgL * stabilizerToChlorineRatio;
    if (fromStabilizer < WaterParameter.freeChlorine.idealMin) {
      return WaterParameter.freeChlorine.idealMin;
    }
    if (fromStabilizer > maxTargetFreeChlorineMgL) {
      return maxTargetFreeChlorineMgL;
    }
    return fromStabilizer;
  }

  /// Chlore libre à atteindre pour un traitement choc, en mg/L (annexe À.5).
  static double shockTargetFreeChlorine(double combinedChlorineMgL) {
    return combinedChlorineMgL * shockMultiplier;
  }

  /// Volume d'eau à renouveler, en m3, pour ramener un paramètre non
  /// éliminable de `current` à `target` (annexe À.4).
  ///
  /// Le stabilisant et le calcium ne se detruisent pas : la seule facon de
  /// faire baisser leur concentration est de remplacer une part de l'eau.
  /// Cas de vérification : stabilisant 80 -> 50 dans 40 m3
  /// = 40 x (80 - 50) / 80 = 15 m3.
  static double waterRenewalM3({
    required double volumeM3,
    required double current,
    required double target,
  }) {
    if (volumeM3 <= 0 || current <= 0 || target >= current) {
      return 0.0;
    }
    return volumeM3 * (current - target) / current;
  }

  // ---------------------------------------------------------------------------
  // Corrections, une methode par paramètre.
  // ---------------------------------------------------------------------------

  /// Correction de pH (annexe À.2).
  ///
  /// Dose = écart de pH x volume x 60 g/m3 x (TAC / 100), divise par la
  /// concentration du produit déclaré.
  static DoseRecommendation? phCorrection({
    required PoolConfig config,
    required double? ph,
    required double? tacMgL,
    required int sequenceIndex,
  }) {
    if (ph == null || config.volumeM3 <= 0) {
      return null;
    }
    final double gap = roundGap(ph - WaterParameter.ph.target);
    if (gap.abs() < minPhGap) {
      return null;
    }
    if (WaterParameter.ph.statusOf(ph) == ParameterStatus.ideal) {
      // 7,4 est un bon pH : on ne dose pas pour gagner 0,2 unité.
      return null;
    }

    // Sans mesure de TAC, on suppose le TAC de référence : c'est le cas le plus
    // fréquent et l'erreur reste proportionnelle, jamais d'un ordre de
    // grandeur.
    final double tac = tacMgL ?? referenceTacMgL;
    final double bufferFactor = tac / referenceTacMgL;

    final bool tooHigh = gap > 0;
    final ChemicalProduct product = config.inventory.forRole(
      tooHigh ? ChemicalRole.phMinus : ChemicalRole.phPlus,
    );

    final double magnitude = gap.abs();
    final double activeGrams =
        magnitude *
        config.volumeM3 *
        phGramsPerM3PerUnitAtTac100 *
        bufferFactor;
    final int splits = splitCount(magnitude, maxPhStepPerDose);

    return DoseRecommendation(
      parameter: WaterParameter.ph,
      priority: ActionPriority.ph,
      sequenceIndex: sequenceIndex,
      title: tooHigh ? 'Baisser le pH' : 'Remonter le pH',
      explanation: tooHigh
          ? 'À pH ${WaterParameter.ph.formatValue(ph)} une grande partie du '
                'chlore est inactive : à 7,2 environ 60 % du chlore agit, à 8,0 '
                'il n’en reste qu’un quart. Le TAC mesuré '
                '(${WaterParameter.tac.formatValue(tac)}) fixe la quantité : '
                'plus il est élevé, plus l’eau résiste au changement de pH.'
          : 'Un pH sous 7,0 rend l’eau agressive pour le liner, les joints et '
                'la peau, et fait disparaître le chlore trop vite. On remonte '
                'vers 7,2.',
      quantity: productQuantity(activeGrams, product),
      unit: product.unit,
      splitCount: splits,
      product: product,
      currentValue: ph,
      targetValue: WaterParameter.ph.target,
      warning: splits > 1
          ? 'À fractionner en $splits apports espacés d’au moins 4 heures, '
                'filtration en marche : un apport unique crée un point de '
                'concentration qui attaque le revêtement.'
          : null,
    );
  }

  /// Correction de TAC (annexe À.4). Se fait AVANT le pH.
  static DoseRecommendation? alkalinityCorrection({
    required PoolConfig config,
    required double? tacMgL,
    required int sequenceIndex,
  }) {
    if (tacMgL == null || config.volumeM3 <= 0) {
      return null;
    }
    if (WaterParameter.tac.statusOf(tacMgL) == ParameterStatus.ideal) {
      return null;
    }

    final double target = correctionTarget(WaterParameter.tac, tacMgL);
    final double gap = roundGap(target - tacMgL);
    if (gap == 0) {
      return null;
    }

    final bool tooLow = gap > 0;
    final ChemicalProduct product = config.inventory.forRole(
      tooLow ? ChemicalRole.alkalinityUp : ChemicalRole.alkalinityDown,
    );
    final double coefficient = tooLow
        ? tacUpGramsPerM3PerMgL
        : tacDownGramsPerM3PerMgL;

    final double magnitude = gap.abs();
    final double activeGrams = magnitude * config.volumeM3 * coefficient;
    final int splits = splitCount(magnitude, maxTacStepPerDoseMgL);

    final String splitWarning = splits > 1
        ? 'À fractionner en $splits apports espacés de 24 heures, en mesurant '
              'entre chaque : le TAC met une journée à s’homogénéiser.'
        : '';
    final String phWarning = tooLow
        ? ''
        : 'La baisse de TAC fait chuter le pH en même temps : mesurez le pH '
              'après chaque apport avant de le corriger.';

    return DoseRecommendation(
      parameter: WaterParameter.tac,
      priority: ActionPriority.alkalinity,
      sequenceIndex: sequenceIndex,
      title: tooLow ? 'Remonter le TAC' : 'Baisser le TAC',
      explanation: tooLow
          ? 'Le TAC est le pouvoir tampon de l’eau. Sous 80 mg/L le pH part '
                'dans tous les sens et chaque correction de pH ne tient pas. '
                'C’est pour cela qu’on corrige le TAC en premier.'
          : 'Au-dessus de 120 mg/L le pH devient très difficile à faire '
                'descendre et l’eau a tendance à entartrer et à se troubler.',
      quantity: productQuantity(activeGrams, product),
      unit: product.unit,
      splitCount: splits,
      product: product,
      currentValue: tacMgL,
      targetValue: target,
      warning: _joinWarnings(<String>[splitWarning, phWarning]),
    );
  }

  /// Correction du chlore libre d'entretien (annexe À.3).
  static DoseRecommendation? chlorineCorrection({
    required PoolConfig config,
    required double? freeChlorineMgL,
    required double? stabilizerMgL,
    required int sequenceIndex,
  }) {
    if (freeChlorineMgL == null || config.volumeM3 <= 0) {
      return null;
    }
    if (!config.usesChlorine) {
      // Brome ou oxygène actif : il n'y a pas de chlore à doser.
      return null;
    }

    final double target = targetFreeChlorine(stabilizerMgL);

    if (freeChlorineMgL > WaterParameter.freeChlorine.acceptableMax) {
      // Le chlore en excès ne se retire pas : il se laisse consommer.
      return DoseRecommendation(
        parameter: WaterParameter.freeChlorine,
        priority: ActionPriority.chlorine,
        sequenceIndex: sequenceIndex,
        title: 'Suspendre les apports de chlore',
        explanation:
            'Le chlore libre dépasse 3 mg/L : il pique les yeux et '
            'attaque les joints. Il ne se retire pas, il se consomme. Arrêtez '
            'les apports, laissez filtrer et découvrez le bassin en journée : '
            'les UV feront baisser la valeur en un à deux jours.',
        quantity: 0.0,
        unit: DoseUnit.gram,
        splitCount: 1,
        currentValue: freeChlorineMgL,
        targetValue: target,
        warning: 'Baignade déconseillée au-delà de 3 mg/L de chlore libre.',
      );
    }

    final double gap = roundGap(target - freeChlorineMgL);
    // Sous la résolution du testeur, l'apport serait invisible à la mesure
    // suivante et ferait douter de la recommandation.
    if (gap < minChlorineGapMgL) {
      return null;
    }

    // Stabilisant saturé : ajouter du chlore stabilisé aggraverait la cause.
    final bool stabilizerSaturated =
        stabilizerMgL != null &&
        stabilizerMgL > WaterParameter.stabilizer.acceptableMax;
    final ChemicalRole role =
        stabilizerSaturated || !config.usesStabilizedChlorine
        ? ChemicalRole.chlorineShock
        : ChemicalRole.chlorineSlow;
    final ChemicalProduct product = config.inventory.forRole(role);

    final double activeGrams = gap * config.volumeM3 * gramsPerM3PerMgL;

    return DoseRecommendation(
      parameter: WaterParameter.freeChlorine,
      priority: ActionPriority.chlorine,
      sequenceIndex: sequenceIndex,
      title: 'Remonter le chlore libre',
      explanation: stabilizerMgL == null
          ? 'Le chlore libre est le désinfectant réellement disponible. On '
                'vise ${WaterParameter.freeChlorine.formatValue(target)}.'
          : 'Avec un stabilisant à '
                '${WaterParameter.stabilizer.formatValue(stabilizerMgL)}, il faut '
                '${WaterParameter.freeChlorine.formatValue(target)} de chlore '
                'libre pour la même désinfection : le stabilisant protège le '
                'chlore des UV mais le freine aussi.',
      quantity: productQuantity(activeGrams, product),
      unit: product.unit,
      splitCount: 1,
      product: product,
      currentValue: freeChlorineMgL,
      targetValue: target,
      warning: stabilizerSaturated
          ? 'Stabilisant au-dessus de 75 mg/L : utilisez un chlore NON '
                'stabilisé, sinon chaque apport aggrave le blocage du chlore.'
          : null,
    );
  }

  /// Traitement choc contre les chloramines (annexe À.5).
  static DoseRecommendation? shockCorrection({
    required PoolConfig config,
    required double? combinedChlorineMgL,
    required double? freeChlorineMgL,
    required int sequenceIndex,
  }) {
    if (combinedChlorineMgL == null || config.volumeM3 <= 0) {
      return null;
    }
    if (!config.usesChlorine) {
      return null;
    }
    if (combinedChlorineMgL <= WaterParameter.combinedChlorine.acceptableMax) {
      return null;
    }

    final double target = shockTargetFreeChlorine(combinedChlorineMgL);
    // Le chlore libre déjà present compte dans la cible.
    final double gap = roundGap(target - (freeChlorineMgL ?? 0.0));
    if (gap <= 0) {
      return null;
    }

    // Le choc se fait toujours avec un chlore non stabilisé : la dose est trop
    // forte pour ajouter autant de stabilisant d'un coup.
    final ChemicalProduct product = config.inventory.forRole(
      ChemicalRole.chlorineShock,
    );
    final double activeGrams = gap * config.volumeM3 * gramsPerM3PerMgL;

    return DoseRecommendation(
      parameter: WaterParameter.combinedChlorine,
      priority: ActionPriority.urgent,
      sequenceIndex: sequenceIndex,
      title: 'Traitement choc',
      explanation:
          'Le chlore combiné à '
          '${WaterParameter.combinedChlorine.formatValue(combinedChlorineMgL)} '
          'est du chlore déjà consommé : c’est lui qui pique les yeux et qui '
          'donne l’odeur de « chlore ». Il ne disparaît qu’au-dessus d’environ '
          '10 fois sa valeur en chlore libre, soit '
          '${WaterParameter.freeChlorine.formatValue(target)}. En dessous, on '
          'nourrit le problème au lieu de le détruire.',
      quantity: productQuantity(activeGrams, product),
      unit: product.unit,
      splitCount: 1,
      product: product,
      currentValue: combinedChlorineMgL,
      targetValue: target,
      warning:
          'Baignade interdite jusqu’au retour du chlore libre sous '
          '3 mg/L. Filtration en continu pendant le traitement, et bassin '
          'découvert le soir de l’apport.',
    );
  }

  /// Correction du stabilisant (annexe À.4).
  ///
  /// À la hausse c'est un dosage ; à la baisse c'est un renouvellement d'eau,
  /// parce que l'acide cyanurique ne se détruit pas.
  static DoseRecommendation? stabilizerCorrection({
    required PoolConfig config,
    required double? stabilizerMgL,
    required int sequenceIndex,
  }) {
    if (stabilizerMgL == null || config.volumeM3 <= 0) {
      return null;
    }
    if (WaterParameter.stabilizer.statusOf(stabilizerMgL) ==
        ParameterStatus.ideal) {
      return null;
    }

    final double target = correctionTarget(
      WaterParameter.stabilizer,
      stabilizerMgL,
    );

    if (stabilizerMgL > target) {
      final double renewal = waterRenewalM3(
        volumeM3: config.volumeM3,
        current: stabilizerMgL,
        target: target,
      );
      return DoseRecommendation(
        parameter: WaterParameter.stabilizer,
        priority: ActionPriority.balance,
        sequenceIndex: sequenceIndex,
        title: 'Renouveler une partie de l’eau',
        explanation:
            'Le stabilisant ne se détruit pas et ne s’évapore pas : il '
            's’accumule à chaque galet. À '
            '${WaterParameter.stabilizer.formatValue(stabilizerMgL)} il bloque '
            'le chlore. Vidanger et remplir '
            '${DoseRecommendation.formatQuantity(renewal, DoseUnit.cubicMeter)} '
            'ramène la valeur vers '
            '${WaterParameter.stabilizer.formatValue(target)}.',
        quantity: renewal,
        unit: DoseUnit.cubicMeter,
        splitCount: 1,
        currentValue: stabilizerMgL,
        targetValue: target,
        warning:
            'Vidangez par le bas et remplissez en filtrant : le TH et le '
            'TAC de l’eau neuve devront être revérifiés ensuite.',
      );
    }

    if (!config.usesChlorine) {
      // Sans chlore, le stabilisant n'a aucune utilite.
      return null;
    }

    final ChemicalProduct product = config.inventory.forRole(
      ChemicalRole.stabilizer,
    );
    final double gap = roundGap(target - stabilizerMgL);
    final double activeGrams = gap * config.volumeM3 * gramsPerM3PerMgL;

    return DoseRecommendation(
      parameter: WaterParameter.stabilizer,
      priority: ActionPriority.balance,
      sequenceIndex: sequenceIndex,
      title: 'Ajouter du stabilisant',
      explanation:
          'Sous 20 mg/L de stabilisant, le soleil détruit la moitié du '
          'chlore libre en deux à trois heures. Le stabilisant sert d’écran UV '
          'au chlore.',
      quantity: productQuantity(activeGrams, product),
      unit: product.unit,
      splitCount: 1,
      product: product,
      currentValue: stabilizerMgL,
      targetValue: target,
      warning:
          'Versez dans le panier du skimmer, filtration en marche : '
          'l’acide cyanurique se dissout lentement.',
    );
  }

  /// Correction du TH (durete calcique).
  static DoseRecommendation? hardnessCorrection({
    required PoolConfig config,
    required double? thMgL,
    required int sequenceIndex,
  }) {
    if (thMgL == null || config.volumeM3 <= 0) {
      return null;
    }
    if (WaterParameter.th.statusOf(thMgL) == ParameterStatus.ideal) {
      return null;
    }

    final double target = correctionTarget(WaterParameter.th, thMgL);

    if (thMgL > target) {
      final double renewal = waterRenewalM3(
        volumeM3: config.volumeM3,
        current: thMgL,
        target: target,
      );
      return DoseRecommendation(
        parameter: WaterParameter.th,
        priority: ActionPriority.balance,
        sequenceIndex: sequenceIndex,
        title: 'Diluer l’eau trop calcaire',
        explanation:
            'À ${WaterParameter.th.formatValue(thMgL)} de TH, le '
            'calcaire se dépose sur les parois, dans le filtre et sur la '
            'cellule d’électrolyse. Le calcium ne s’élimine pas : il se dilue.',
        quantity: renewal,
        unit: DoseUnit.cubicMeter,
        splitCount: 1,
        currentValue: thMgL,
        targetValue: target,
        warning:
            'À ne faire que si l’eau de remplissage est moins calcaire '
            'que celle du bassin, sinon la dilution n’apporte rien.',
      );
    }

    final ChemicalProduct product = config.inventory.forRole(
      ChemicalRole.hardnessUp,
    );
    final double gap = roundGap(target - thMgL);
    final double activeGrams = gap * config.volumeM3 * hardnessGramsPerM3PerMgL;

    return DoseRecommendation(
      parameter: WaterParameter.th,
      priority: ActionPriority.balance,
      sequenceIndex: sequenceIndex,
      title: 'Durcir l’eau',
      explanation:
          'Une eau trop douce (sous 100 mg/L) va chercher le calcium '
          'là où il se trouve : dans les joints de carrelage, le béton et les '
          'pièces à sceller. Le durcisseur lui en fournit.',
      quantity: productQuantity(activeGrams, product),
      unit: product.unit,
      splitCount: 1,
      product: product,
      currentValue: thMgL,
      targetValue: target,
    );
  }

  /// Correction du sel, uniquement pour un bassin à électrolyse.
  static DoseRecommendation? saltCorrection({
    required PoolConfig config,
    required double? saltGPerL,
    required int sequenceIndex,
  }) {
    if (saltGPerL == null || config.volumeM3 <= 0) {
      return null;
    }
    if (config.treatment != TreatmentType.salt) {
      // Sans électrolyseur, la salinité n'a pas de consigne à respecter.
      return null;
    }
    if (WaterParameter.salt.statusOf(saltGPerL) == ParameterStatus.ideal) {
      return null;
    }

    final double target = correctionTarget(WaterParameter.salt, saltGPerL);

    if (saltGPerL > target) {
      final double renewal = waterRenewalM3(
        volumeM3: config.volumeM3,
        current: saltGPerL,
        target: target,
      );
      return DoseRecommendation(
        parameter: WaterParameter.salt,
        priority: ActionPriority.balance,
        sequenceIndex: sequenceIndex,
        title: 'Diluer le sel',
        explanation:
            'Au-dessus de 5 g/L, la cellule d’électrolyse s’use plus '
            'vite et l’eau devient corrosive pour les pièces métalliques. Le '
            'sel ne s’évapore pas : il se dilue.',
        quantity: renewal,
        unit: DoseUnit.cubicMeter,
        splitCount: 1,
        currentValue: saltGPerL,
        targetValue: target,
      );
    }

    final ChemicalProduct product = config.inventory.forRole(ChemicalRole.salt);
    final double gap = roundGap(target - saltGPerL);
    final double activeGrams = gap * config.volumeM3 * gramsPerM3PerGPerL;

    return DoseRecommendation(
      parameter: WaterParameter.salt,
      priority: ActionPriority.balance,
      sequenceIndex: sequenceIndex,
      title: 'Ajouter du sel',
      explanation:
          'Sous 3 g/L la cellule ne produit plus assez de chlore et '
          'se met en défaut. On vise '
          '${WaterParameter.salt.formatValue(target)}.',
      quantity: productQuantity(activeGrams, product),
      unit: product.unit,
      splitCount: 1,
      product: product,
      currentValue: saltGPerL,
      targetValue: target,
      warning:
          'Électrolyseur à l’arrêt, pompe en marche, sel versé dans le '
          'grand bain : comptez 24 heures de brassage avant de remesurer.',
    );
  }

  // ---------------------------------------------------------------------------
  // Assemblage
  // ---------------------------------------------------------------------------

  /// Toutes les actions à mener, dans l'ordre métier.
  ///
  /// Les corrections sont PRODUITES dans l'ordre de la fiche de mesure (pH,
  /// chlore, TAC, ...) puis TRIEES explicitement sur (priorité, ordre
  /// d'ajout) : c'est le tri qui garantit l'ordre TAC -> pH -> chlore ->
  /// stabilisant/TH/sel, jamais l'ordre d'ecriture du code.
  static List<DoseRecommendation> recommend({
    required PoolConfig config,
    required WaterReading reading,
  }) {
    // Un volume nul ou une mesure vide ne peuvent produire aucune dose : sans
    // volume la dose n'a pas de sens, sans mesure il n'y a rien à corriger.
    if (config.volumeM3 <= 0 || reading.isEmpty) {
      return const <DoseRecommendation>[];
    }

    final List<DoseRecommendation> actions = <DoseRecommendation>[];
    int sequence = 0;

    void add(DoseRecommendation? action) {
      if (action != null) {
        actions.add(action);
      }
      sequence++;
    }

    add(
      phCorrection(
        config: config,
        ph: reading.ph,
        tacMgL: reading.tac,
        sequenceIndex: sequence,
      ),
    );
    add(
      chlorineCorrection(
        config: config,
        freeChlorineMgL: reading.freeChlorine,
        stabilizerMgL: reading.stabilizer,
        sequenceIndex: sequence,
      ),
    );
    add(
      shockCorrection(
        config: config,
        combinedChlorineMgL: reading.combinedChlorine,
        freeChlorineMgL: reading.freeChlorine,
        sequenceIndex: sequence,
      ),
    );
    add(
      alkalinityCorrection(
        config: config,
        tacMgL: reading.tac,
        sequenceIndex: sequence,
      ),
    );
    add(
      hardnessCorrection(
        config: config,
        thMgL: reading.th,
        sequenceIndex: sequence,
      ),
    );
    add(
      stabilizerCorrection(
        config: config,
        stabilizerMgL: reading.stabilizer,
        sequenceIndex: sequence,
      ),
    );
    add(
      saltCorrection(
        config: config,
        saltGPerL: reading.salt,
        sequenceIndex: sequence,
      ),
    );

    return DoseRecommendation.sorted(actions);
  }

  /// Assemble les avertissements non vides en un seul texte, ou `null`.
  static String? _joinWarnings(List<String> parts) {
    final List<String> kept = parts
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    if (kept.isEmpty) {
      return null;
    }
    return kept.join(' ');
  }
}
