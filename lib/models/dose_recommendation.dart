import 'chemical_product.dart';
import 'json_tolerant.dart';
import 'water_reading.dart';

/// Rang métier d'une correction.
///
/// L'ordre n'est pas de la présentation, c'est de la chimie : le TAC stabilise
/// le pH, et le pH commande l'efficacite du chlore. Corriger le chlore avant le
/// pH fait consommer du produit pour rien.
enum ActionPriority {
  /// Traitement choc : une eau qui pique ou qui verdit passe avant le confort.
  urgent(0),

  /// TAC : il se corrige en premier, sinon le pH corrige repart.
  alkalinity(1),

  /// pH : il commande la part de chlore réellement actif.
  ph(2),

  /// Chlore d'entretien.
  chlorine(3),

  /// Stabilisant, TH, sel : l'équilibre de fond, sans urgence.
  balance(4),

  /// Information seule, aucun produit à verser.
  information(5);

  const ActionPriority(this.rank);

  /// Rang de tri. Plus petit = à faire en premier.
  final int rank;
}

/// Une action concrete à realiser sur le bassin.
///
/// Immuable, et sans aucune mise en forme d'écran : le formatage de la quantité
/// est ici parce qu'il fait partie du contrat métier (virgule décimale,
/// bascule g/kg et ml/L), pas parce que c'est de la présentation.
class DoseRecommendation {
  const DoseRecommendation({
    required this.parameter,
    required this.priority,
    required this.sequenceIndex,
    required this.title,
    required this.explanation,
    required this.quantity,
    required this.unit,
    required this.splitCount,
    this.product,
    this.currentValue,
    this.targetValue,
    this.warning,
  });

  /// Paramètre corrige. Sert à relier l'action à la mesure affichee.
  final WaterParameter parameter;

  final ActionPriority priority;

  /// Ordre d'ajout par le moteur. Second critère de tri : le tri de Dart n'est
  /// pas garanti stable, deux actions de même rang doivent rester dans l'ordre
  /// ou le moteur les à produites.
  final int sequenceIndex;

  final String title;

  /// Le pourquoi, en francais, affichable tel quel.
  final String explanation;

  /// Quantité totale à apporter, dans l'unite `unit`.
  final double quantity;

  final DoseUnit unit;

  /// Nombre d'apports. Au-delà de 1, l'apport doit être fractionne : un gros
  /// apport en une fois crée un point de concentration qui attaque le liner et
  /// fausse la mesure suivante.
  final int splitCount;

  /// Produit utilisé. Nul quand l'action n'est pas un dosage (renouvellement
  /// d'eau, information).
  final ChemicalProduct? product;

  final double? currentValue;
  final double? targetValue;

  /// Avertissement obligatoire quand il y en à un (baignade interdite, chute
  /// de pH attendue, fractionnement).
  final String? warning;

  /// Quantité par apport, quand la dose est fractionnee.
  double get quantityPerDose =>
      splitCount <= 1 ? quantity : quantity / splitCount;

  bool get isSplit => splitCount > 1;

  /// Quantité totale mise en forme : « 250 g », « 1,44 kg », « 400 ml »,
  /// « 1,5 L », « 15 m³ ».
  String get formattedQuantity => formatQuantity(quantity, unit);

  /// Quantité d'un seul apport mise en forme.
  String get formattedQuantityPerDose => formatQuantity(quantityPerDose, unit);

  /// Seuil de bascule vers l'unite superieure.
  ///
  /// En dessous de 1 000 g on parle en grammes (« 250 g » est plus parlant que
  /// « 0,25 kg »), au-dessus en kilogrammes. Même logique pour ml et L.
  static const double _unitBreak = 1000.0;

  /// Met en forme une quantité selon les règles d'affichage du projet.
  ///
  /// - sous le seuil : entier arrondi, pas de décimale inutile (250 g, 400 ml) ;
  /// - au-dessus : deux décimales au maximum, zéros de fin supprimés
  ///   (1,44 kg mais 1,5 L et non 1,50 L) ;
  /// - séparateur décimal : la virgule.
  static String formatQuantity(double quantity, DoseUnit unit) {
    switch (unit) {
      case DoseUnit.gram:
        if (quantity < _unitBreak) {
          return '${_formatNumber(quantity, 0)} g';
        }
        return '${_formatNumber(quantity / _unitBreak, 2)} kg';
      case DoseUnit.milliliter:
        if (quantity < _unitBreak) {
          return '${_formatNumber(quantity, 0)} ml';
        }
        return '${_formatNumber(quantity / _unitBreak, 2)} L';
      case DoseUnit.cubicMeter:
        // Un volume d'eau à renouveler se lit au dixieme de m3 ; il n'y a pas
        // d'unite superieure utile à l'échelle d'un bassin.
        return '${_formatNumber(quantity, 1)} m³';
    }
  }

  static String _formatNumber(double value, int maxDecimals) {
    final String fixed = value.toStringAsFixed(maxDecimals);
    if (!fixed.contains('.')) {
      return fixed;
    }
    // Retire les zéros de fin puis le point devenu inutile : 1,50 -> 1,5.
    String trimmed = fixed;
    while (trimmed.endsWith('0')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (trimmed.endsWith('.')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.replaceAll('.', ',');
  }

  /// Trie une liste d'actions dans l'ordre métier.
  ///
  /// Tri explicite sur (rang de priorité, ordre d'ajout) : `List.sort` n'est
  /// pas garanti stable en Dart, s'appuyer sur sa stabilite ferait dependre
  /// l'ordre d'affichage de la taille de la liste.
  static List<DoseRecommendation> sorted(List<DoseRecommendation> actions) {
    final List<DoseRecommendation> copy = List<DoseRecommendation>.from(
      actions,
    );
    copy.sort((DoseRecommendation a, DoseRecommendation b) {
      final int byPriority = a.priority.rank.compareTo(b.priority.rank);
      if (byPriority != 0) {
        return byPriority;
      }
      return a.sequenceIndex.compareTo(b.sequenceIndex);
    });
    return copy;
  }

  DoseRecommendation copyWith({
    WaterParameter? parameter,
    ActionPriority? priority,
    int? sequenceIndex,
    String? title,
    String? explanation,
    double? quantity,
    DoseUnit? unit,
    int? splitCount,
    ChemicalProduct? product,
    double? currentValue,
    double? targetValue,
    String? warning,
  }) {
    return DoseRecommendation(
      parameter: parameter ?? this.parameter,
      priority: priority ?? this.priority,
      sequenceIndex: sequenceIndex ?? this.sequenceIndex,
      title: title ?? this.title,
      explanation: explanation ?? this.explanation,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      splitCount: splitCount ?? this.splitCount,
      product: product ?? this.product,
      currentValue: currentValue ?? this.currentValue,
      targetValue: targetValue ?? this.targetValue,
      warning: warning ?? this.warning,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'parameter': parameter.name,
      'priority': priority.name,
      'sequenceIndex': sequenceIndex,
      'title': title,
      'explanation': explanation,
      'quantity': quantity,
      'unit': unit.name,
      'splitCount': splitCount,
      'product': product?.toJson(),
      'currentValue': currentValue,
      'targetValue': targetValue,
      'warning': warning,
    };
  }

  factory DoseRecommendation.fromJson(Object? raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return DoseRecommendation(
      parameter: readEnum(
        json,
        'parameter',
        WaterParameter.values,
        WaterParameter.ph,
      ),
      priority: readEnum(
        json,
        'priority',
        ActionPriority.values,
        ActionPriority.information,
      ),
      sequenceIndex: readInt(json, 'sequenceIndex', 0),
      title: readString(json, 'title', 'Action'),
      explanation: readString(json, 'explanation', ''),
      // Une quantité négative relue du disque n'a aucun sens : on la ramène à
      // zéro, l'action sera affichee sans dose plutôt que de faire retirer du
      // produit du bassin.
      quantity: clampDouble(
        readDouble(json, 'quantity', 0.0),
        0.0,
        double.maxFinite,
      ),
      unit: readEnum(json, 'unit', DoseUnit.values, DoseUnit.gram),
      // Au moins un apport : un fractionnement à zéro rendrait la division par
      // `splitCount` infinie.
      splitCount: readInt(json, 'splitCount', 1).clamp(1, 100),
      product: json['product'] == null
          ? null
          : ChemicalProduct.fromJson(json['product']),
      currentValue: readNullableDouble(json, 'currentValue'),
      targetValue: readNullableDouble(json, 'targetValue'),
      warning: readNullableString(json, 'warning'),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DoseRecommendation &&
        other.parameter == parameter &&
        other.priority == priority &&
        other.sequenceIndex == sequenceIndex &&
        other.title == title &&
        other.explanation == explanation &&
        other.quantity == quantity &&
        other.unit == unit &&
        other.splitCount == splitCount &&
        other.product == product &&
        other.currentValue == currentValue &&
        other.targetValue == targetValue &&
        other.warning == warning;
  }

  @override
  int get hashCode => Object.hash(
    parameter,
    priority,
    sequenceIndex,
    title,
    explanation,
    quantity,
    unit,
    splitCount,
    product,
    currentValue,
    targetValue,
    warning,
  );

  @override
  String toString() => 'DoseRecommendation($title, $formattedQuantity)';
}
