import 'json_tolerant.dart';

enum CoverPosition {
  closed,
  partiallyOpen,
  open,

  unknown,
}

enum CoverMotion { idle, opening, closing }

enum PumpState {

  unknown,
  off,
  on,
}

class CoverState {
  const CoverState({
    this.position = CoverPosition.unknown,
    this.motion = CoverMotion.idle,
    this.openRatio = 0.0,
    this.isEstimated = true,
    this.lastMovedAt,
    this.pump = PumpState.unknown,
    this.pumpPowerW,
  });

  static const CoverState unknownState = CoverState();

  final CoverPosition position;

  final CoverMotion motion;

  final double openRatio;

  final bool isEstimated;

  final DateTime? lastMovedAt;

  final PumpState pump;

  final double? pumpPowerW;

  bool get isMoving => motion != CoverMotion.idle;

  bool get isPumpRunning => pump == PumpState.on;

  String get formattedOpenRatio => '${(openRatio * 100).round()} %';

  static CoverPosition positionFromRatio(double ratio) {
    if (ratio <= 0.02) {
      return CoverPosition.closed;
    }
    if (ratio >= 0.98) {
      return CoverPosition.open;
    }
    return CoverPosition.partiallyOpen;
  }

  CoverState copyWith({
    CoverPosition? position,
    CoverMotion? motion,
    double? openRatio,
    bool? isEstimated,
    DateTime? lastMovedAt,
    PumpState? pump,
    double? pumpPowerW,
  }) {
    return CoverState(
      position: position ?? this.position,
      motion: motion ?? this.motion,
      openRatio: openRatio ?? this.openRatio,
      isEstimated: isEstimated ?? this.isEstimated,
      lastMovedAt: lastMovedAt ?? this.lastMovedAt,
      pump: pump ?? this.pump,
      pumpPowerW: pumpPowerW ?? this.pumpPowerW,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'position': position.name,
      'motion': motion.name,
      'openRatio': openRatio,
      'isEstimated': isEstimated,
      'lastMovedAt': lastMovedAt?.toIso8601String(),
      'pump': pump.name,
      'pumpPowerW': pumpPowerW,
    };
  }

  factory CoverState.fromJson(Object? raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return CoverState(
      position: readEnum(
        json,
        'position',
        CoverPosition.values,
        CoverPosition.unknown,
      ),
      motion: CoverMotion.idle,
      openRatio: clampDouble(readDouble(json, 'openRatio', 0.0), 0.0, 1.0),

      isEstimated: readBool(json, 'isEstimated', true),
      lastMovedAt: readNullableDateTime(json, 'lastMovedAt'),
      pump: readEnum(json, 'pump', PumpState.values, PumpState.unknown),
      pumpPowerW: readNullableDouble(json, 'pumpPowerW'),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CoverState &&
        other.position == position &&
        other.motion == motion &&
        other.openRatio == openRatio &&
        other.isEstimated == isEstimated &&
        other.lastMovedAt == lastMovedAt &&
        other.pump == pump &&
        other.pumpPowerW == pumpPowerW;
  }

  @override
  int get hashCode => Object.hash(
    position,
    motion,
    openRatio,
    isEstimated,
    lastMovedAt,
    pump,
    pumpPowerW,
  );

  @override
  String toString() =>
      'CoverState(${position.name}, ${motion.name}, $formattedOpenRatio)';
}
