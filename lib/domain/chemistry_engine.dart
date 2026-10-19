import '../models/chemical_product.dart';
import '../models/dose_recommendation.dart';
import '../models/pool_config.dart';
import '../models/water_reading.dart';

class ChemistryEngine {

  static const double phGramsPerM3PerUnitAtTac100 = 60.0;

  static const double referenceTacMgL = 100.0;

  static const double maxPhStepPerDose = 0.30;

  static const double minPhGap = 0.10;

  static const double tacUpGramsPerM3PerMgL = 1.8;

  static const double tacDownGramsPerM3PerMgL = 1.5;

  static const double maxTacStepPerDoseMgL = 20.0;

  static const double stabilizerToChlorineRatio = 0.075;

  static const double maxTargetFreeChlorineMgL = 4.0;

  static const double minChlorineGapMgL = 0.30;

  static const double shockMultiplier = 10.0;

  static const double hardnessGramsPerM3PerMgL = 1.48;

  static const double gramsPerM3PerMgL = 1.0;

  static const double gramsPerM3PerGPerL = 1000.0;

  static const double splitEpsilon = 1e-9;

  static double roundGap(double gap) {
    return (gap * 100).roundToDouble() / 100;
  }

  static int splitCount(double need, double maxPerDose) {
    if (maxPerDose <= 0 || need <= 0) {
      return 1;
    }
    final int count = ((need / maxPerDose) - splitEpsilon).ceil();
    return count < 1 ? 1 : count;
  }

  static double productQuantity(double activeGrams, ChemicalProduct product) {
    return activeGrams / product.activeFraction;
  }

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

  static double shockTargetFreeChlorine(double combinedChlorineMgL) {
    return combinedChlorineMgL * shockMultiplier;
  }

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

      return null;
    }

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

      return null;
    }

    final double target = targetFreeChlorine(stabilizerMgL);

    if (freeChlorineMgL > WaterParameter.freeChlorine.acceptableMax) {

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

    if (gap < minChlorineGapMgL) {
      return null;
    }

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

    final double gap = roundGap(target - (freeChlorineMgL ?? 0.0));
    if (gap <= 0) {
      return null;
    }

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

  static DoseRecommendation? saltCorrection({
    required PoolConfig config,
    required double? saltGPerL,
    required int sequenceIndex,
  }) {
    if (saltGPerL == null || config.volumeM3 <= 0) {
      return null;
    }
    if (config.treatment != TreatmentType.salt) {

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

  static List<DoseRecommendation> recommend({
    required PoolConfig config,
    required WaterReading reading,
  }) {

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
