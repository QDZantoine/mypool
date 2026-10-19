import 'chemical_product.dart';
import 'json_tolerant.dart';
import 'water_reading.dart';

enum ActionPriority {

  urgent(0),

  alkalinity(1),

  ph(2),

  chlorine(3),

  balance(4),

  information(5);

  const ActionPriority(this.rank);

  final int rank;
}

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

  final WaterParameter parameter;

  final ActionPriority priority;

  final int sequenceIndex;

  final String title;

  final String explanation;

  final double quantity;

  final DoseUnit unit;

  final int splitCount;

  final ChemicalProduct? product;

  final double? currentValue;
  final double? targetValue;

  final String? warning;

  double get quantityPerDose =>
      splitCount <= 1 ? quantity : quantity / splitCount;

  bool get isSplit => splitCount > 1;

  String get formattedQuantity => formatQuantity(quantity, unit);

  String get formattedQuantityPerDose => formatQuantity(quantityPerDose, unit);

  static const double _unitBreak = 1000.0;

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

        return '${_formatNumber(quantity, 1)} m³';
    }
  }

  static String _formatNumber(double value, int maxDecimals) {
    final String fixed = value.toStringAsFixed(maxDecimals);
    if (!fixed.contains('.')) {
      return fixed;
    }

    String trimmed = fixed;
    while (trimmed.endsWith('0')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (trimmed.endsWith('.')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.replaceAll('.', ',');
  }

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

      quantity: clampDouble(
        readDouble(json, 'quantity', 0.0),
        0.0,
        double.maxFinite,
      ),
      unit: readEnum(json, 'unit', DoseUnit.values, DoseUnit.gram),

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
