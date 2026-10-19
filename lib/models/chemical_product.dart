import 'json_tolerant.dart';

enum ChemicalRole {

  phMinus,

  phPlus,

  alkalinityUp,

  alkalinityDown,

  chlorineSlow,

  chlorineShock,

  chlorineLiquid,

  stabilizer,

  hardnessUp,

  salt,
}

enum DoseUnit {

  gram,

  milliliter,

  cubicMeter,
}

class ChemicalProduct {
  const ChemicalProduct({
    required this.id,
    required this.label,
    required this.role,
    required this.unit,
    required this.activePercent,
    this.activeSubstance = '',
  });

  final String id;

  final String label;

  final ChemicalRole role;

  final DoseUnit unit;

  final double activePercent;

  final String activeSubstance;

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

class ChemicalInventory {
  const ChemicalInventory({required this.products});

  final Map<ChemicalRole, ChemicalProduct> products;

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

  static const ChemicalInventory standard = ChemicalInventory(
    products: defaults,
  );

  static ChemicalProduct defaultFor(ChemicalRole role) {

    return defaults[role]!;
  }

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
