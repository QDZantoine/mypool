import 'json_tolerant.dart';

/// Rôle d'un produit dans la correction de l'eau.
///
/// Le rôle, et non le nom commercial, determine le calcul : deux marques de
/// bicarbonate se dosent avec le même coefficient des lors que leur
/// concentration est déclarée.
enum ChemicalRole {
  /// Correcteur de pH à la baisse (bisulfate de sodium, acide).
  phMinus,

  /// Correcteur de pH à la hausse (carbonate de sodium).
  phPlus,

  /// Correcteur de TAC à la hausse (bicarbonate de sodium).
  alkalinityUp,

  /// Correcteur de TAC à la baisse (acide).
  alkalinityDown,

  /// Chlore d'entretien, généralement stabilisé (galets, granulés).
  chlorineSlow,

  /// Chlore de traitement choc, non stabilisé et à dissolution rapide.
  chlorineShock,

  /// Chlore liquide (hypochlorite de sodium).
  chlorineLiquid,

  /// Stabilisant (acide cyanurique).
  stabilizer,

  /// Correcteur de durete calcique à la hausse (chlorure de calcium).
  hardnessUp,

  /// Sel pour électrolyseur (chlorure de sodium).
  salt,
}

/// Unité dans laquelle une dose s'exprime.
enum DoseUnit {
  /// Produit solide, dose en grammes (affiche en g ou kg).
  gram,

  /// Produit liquide, dose en millilitres (affiche en ml ou L).
  milliliter,

  /// Pas un produit : volume d'eau à renouveler, en metres cubes.
  cubicMeter,
}

/// Un produit tel que l'utilisateur le déclare, avec sa concentration.
///
/// La concentration est le coeur du modèle : le moteur de dosage calcule
/// d'abord une masse de matière active, puis la divise par cette concentration.
/// Un chlore à 90 % et un chlore à 56 % ne donnent donc pas la même quantité à
/// verser pour le même effet dans l'eau.
class ChemicalProduct {
  const ChemicalProduct({
    required this.id,
    required this.label,
    required this.role,
    required this.unit,
    required this.activePercent,
    this.activeSubstance = '',
  });

  /// Identifiant stable, utilisé comme clé de persistance.
  final String id;

  /// Libellé affichable, en francais.
  final String label;

  final ChemicalRole role;

  final DoseUnit unit;

  /// Pourcentage de matière active.
  ///
  /// Pour un solide c'est un pourcentage massique : 100 g de produit à 90 %
  /// apportent 90 g de matière active.
  /// Pour un liquide c'est la convention commerciale du « chlore actif »,
  /// exprimée en poids/volume : 1 L d'eau de Javel à 9,6 % apporte 96 g de
  /// chlore actif. Une seule formule couvre donc les deux cas, sans avoir à
  /// connaitre la densité du produit.
  final double activePercent;

  /// Nom chimique, affiche à titre pédagogique.
  final String activeSubstance;

  /// Facteur de conversion « masse de matière active » -> « quantité à verser ».
  ///
  /// Borne à 1 % au minimum : une concentration nulle ou négative relue d'une
  /// préférence corrompue ferait diverger la dose vers l'infini.
  double get activeFraction => clampDouble(activePercent, 1.0, 100.0) / 100.0;

  ChemicalProduct copyWith({
    String? id,
    String? label,
    ChemicalRole? role,
    DoseUnit? unit,
    double? activePercent,
    String? activeSubstance,
  }) {
    return ChemicalProduct(
      id: id ?? this.id,
      label: label ?? this.label,
      role: role ?? this.role,
      unit: unit ?? this.unit,
      activePercent: activePercent ?? this.activePercent,
      activeSubstance: activeSubstance ?? this.activeSubstance,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'role': role.name,
      'unit': unit.name,
      'activePercent': activePercent,
      'activeSubstance': activeSubstance,
    };
  }

  /// Reconstruit un produit. Un rôle inconnu retombe sur le chlore d'entretien
  /// et une concentration illisible sur 100 % : l'application reste ouvrable,
  /// l'utilisateur corrigera la fiche produit.
  factory ChemicalProduct.fromJson(Object? raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    final ChemicalRole role = readEnum(
      json,
      'role',
      ChemicalRole.values,
      ChemicalRole.chlorineSlow,
    );
    final ChemicalProduct fallback = ChemicalInventory.defaultFor(role);
    return ChemicalProduct(
      id: readString(json, 'id', fallback.id),
      label: readString(json, 'label', fallback.label),
      role: role,
      unit: readEnum(json, 'unit', DoseUnit.values, fallback.unit),
      activePercent: clampDouble(
        readDouble(json, 'activePercent', fallback.activePercent),
        1.0,
        100.0,
      ),
      activeSubstance: readString(
        json,
        'activeSubstance',
        fallback.activeSubstance,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChemicalProduct &&
        other.id == id &&
        other.label == label &&
        other.role == role &&
        other.unit == unit &&
        other.activePercent == activePercent &&
        other.activeSubstance == activeSubstance;
  }

  @override
  int get hashCode =>
      Object.hash(id, label, role, unit, activePercent, activeSubstance);

  @override
  String toString() => 'ChemicalProduct($id, $activePercent%)';
}

/// L'armoire à produits déclarée par l'utilisateur : un produit par rôle.
///
/// Le moteur de dosage n'interroge jamais que cet inventaire. C'est ce qui
/// garantit qu'aucune concentration n'est figée dans le code de calcul.
class ChemicalInventory {
  const ChemicalInventory({required this.products});

  /// Un produit par rôle. Les rôles absents sont completes par les défauts.
  final Map<ChemicalRole, ChemicalProduct> products;

  /// Produits par défaut (annexe À.3).
  ///
  /// Les concentrations sont celles des produits du commerce :
  /// - galets de trichloroisocyanurique : 90 % de chlore actif ;
  /// - hypochlorite de calcium (choc) : 56 % ;
  /// - hypochlorite de sodium (liquide) : 9,6 %.
  /// Les correcteurs minéraux purs (bisulfate, carbonate, bicarbonate, acide
  /// cyanurique, sel, chlorure de calcium) sont déclarés à 100 %, ce qui fait
  /// d'eux la référence des coefficients de l'annexe À.
  static const Map<ChemicalRole, ChemicalProduct> defaults =
      <ChemicalRole, ChemicalProduct>{
        ChemicalRole.phMinus: ChemicalProduct(
          id: 'ph_minus_bisulfate',
          label: 'pH moins (poudre)',
          role: ChemicalRole.phMinus,
          unit: DoseUnit.gram,
          activePercent: 100.0,
          activeSubstance: 'bisulfate de sodium',
        ),
        ChemicalRole.phPlus: ChemicalProduct(
          id: 'ph_plus_carbonate',
          label: 'pH plus (poudre)',
          role: ChemicalRole.phPlus,
          unit: DoseUnit.gram,
          activePercent: 100.0,
          activeSubstance: 'carbonate de sodium',
        ),
        ChemicalRole.alkalinityUp: ChemicalProduct(
          id: 'tac_plus_bicarbonate',
          label: 'TAC plus (bicarbonate)',
          role: ChemicalRole.alkalinityUp,
          unit: DoseUnit.gram,
          activePercent: 100.0,
          activeSubstance: 'bicarbonate de sodium',
        ),
        ChemicalRole.alkalinityDown: ChemicalProduct(
          id: 'tac_moins_bisulfate',
          label: 'TAC moins (poudre acide)',
          role: ChemicalRole.alkalinityDown,
          unit: DoseUnit.gram,
          activePercent: 100.0,
          activeSubstance: 'bisulfate de sodium',
        ),
        ChemicalRole.chlorineSlow: ChemicalProduct(
          id: 'chlore_lent_galets',
          label: 'Chlore lent (galets)',
          role: ChemicalRole.chlorineSlow,
          unit: DoseUnit.gram,
          activePercent: 90.0,
          activeSubstance: 'trichloroisocyanurique',
        ),
        ChemicalRole.chlorineShock: ChemicalProduct(
          id: 'chlore_choc_granules',
          label: 'Chlore choc (granulés)',
          role: ChemicalRole.chlorineShock,
          unit: DoseUnit.gram,
          activePercent: 56.0,
          activeSubstance: 'hypochlorite de calcium',
        ),
        ChemicalRole.chlorineLiquid: ChemicalProduct(
          id: 'chlore_liquide',
          label: 'Chlore liquide',
          role: ChemicalRole.chlorineLiquid,
          unit: DoseUnit.milliliter,
          activePercent: 9.6,
          activeSubstance: 'hypochlorite de sodium',
        ),
        ChemicalRole.stabilizer: ChemicalProduct(
          id: 'stabilisant_acide_cyanurique',
          label: 'Stabilisant',
          role: ChemicalRole.stabilizer,
          unit: DoseUnit.gram,
          activePercent: 100.0,
          activeSubstance: 'acide cyanurique',
        ),
        ChemicalRole.hardnessUp: ChemicalProduct(
          id: 'th_plus_chlorure_calcium',
          label: 'TH plus (durcisseur)',
          role: ChemicalRole.hardnessUp,
          unit: DoseUnit.gram,
          activePercent: 100.0,
          activeSubstance: 'chlorure de calcium dihydraté',
        ),
        ChemicalRole.salt: ChemicalProduct(
          id: 'sel_piscine',
          label: 'Sel de piscine',
          role: ChemicalRole.salt,
          unit: DoseUnit.gram,
          activePercent: 100.0,
          activeSubstance: 'chlorure de sodium',
        ),
      };

  /// Inventaire complet par défaut : une piscine utilisable des l'installation.
  static const ChemicalInventory standard = ChemicalInventory(
    products: defaults,
  );

  static ChemicalProduct defaultFor(ChemicalRole role) {
    // Tous les rôles ont un défaut ; le `!` n'est atteignable qu'en cas
    // d'oubli dans la table ci-dessus, ce que les tests vérifient.
    return defaults[role]!;
  }

  /// Le produit déclaré pour ce rôle, ou le produit par défaut.
  ChemicalProduct forRole(ChemicalRole role) {
    return products[role] ?? defaultFor(role);
  }

  ChemicalInventory withProduct(ChemicalProduct product) {
    final Map<ChemicalRole, ChemicalProduct> next =
        Map<ChemicalRole, ChemicalProduct>.from(products);
    next[product.role] = product;
    return ChemicalInventory(products: next);
  }

  ChemicalInventory copyWith({Map<ChemicalRole, ChemicalProduct>? products}) {
    return ChemicalInventory(products: products ?? this.products);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'products': products.values
          .map((ChemicalProduct product) => product.toJson())
          .toList(growable: false),
    };
  }

  /// Reconstruit l'inventaire en completant tout rôle manquant par son défaut.
  /// Un inventaire partiel ou vide reste donc exploitable par le moteur.
  factory ChemicalInventory.fromJson(Object? raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    final Map<ChemicalRole, ChemicalProduct> next =
        Map<ChemicalRole, ChemicalProduct>.from(defaults);
    for (final Map<String, dynamic> entry in readMapList(json, 'products')) {
      final ChemicalProduct product = ChemicalProduct.fromJson(entry);
      next[product.role] = product;
    }
    return ChemicalInventory(products: next);
  }

  @override
  bool operator ==(Object other) {
    if (other is! ChemicalInventory) {
      return false;
    }
    if (other.products.length != products.length) {
      return false;
    }
    for (final ChemicalRole role in products.keys) {
      if (other.products[role] != products[role]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(products.values);

  @override
  String toString() => 'ChemicalInventory(${products.length} produits)';
}
