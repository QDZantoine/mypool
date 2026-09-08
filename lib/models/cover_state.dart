import 'json_tolerant.dart';

/// Position estimée du volet.
///
/// Sans capteur de fin de course remonte par le module, la position est une
/// ESTIMATION calculée depuis le temps de course cumule. Le champ `isEstimated`
/// existe pour que l'interface l'affiche comme telle (règle de sécurité n. 6) :
/// on ne dit jamais « fermé » quand on veut dire « probablement fermé ».
enum CoverPosition {
  closed,
  partiallyOpen,
  open,

  /// Position inconnue : au démarrage, ou après une coupure pendant un
  /// mouvement.
  unknown,
}

/// Mouvement en cours.
///
/// Un mouvement n'existe que tant qu'un doigt est maintenu sur le bouton
/// (règle de sécurité n. 1). Il n'y a donc pas d'etat « en route vers une
/// position cible » : rien ne poursuit un mouvement tout seul.
enum CoverMotion { idle, opening, closing }

/// État de la pompe de filtration.
enum PumpState {
  /// État non encore lu sur le module.
  unknown,
  off,
  on,
}

/// État courant du volet et de la pompe.
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

  /// État initial : on ne sait rien avant d'avoir interrogé le module.
  static const CoverState unknownState = CoverState();

  final CoverPosition position;

  final CoverMotion motion;

  /// Taux d'ouverture estimé, de 0 (fermé) à 1 (ouvert).
  final double openRatio;

  /// `false` seulement si le module remonte une vraie fin de course.
  final bool isEstimated;

  /// Horodatage du dernier mouvement. Fourni par l'appelant : le domaine ne lit
  /// jamais l'horloge lui-même, c'est ce qui rend les calculs reproductibles.
  final DateTime? lastMovedAt;

  final PumpState pump;

  /// Puissance instantanee lue sur le module, en watts. Sert à detecter qu'un
  /// moteur tourne alors qu'on le croit à l'arret.
  final double? pumpPowerW;

  bool get isMoving => motion != CoverMotion.idle;

  bool get isPumpRunning => pump == PumpState.on;

  /// « 0 % », « 45 % », « 100 % »
  String get formattedOpenRatio => '${(openRatio * 100).round()} %';

  /// Déduit la position du taux d'ouverture.
  ///
  /// Les 2 % de marge aux extrémités absorbent l'imprecision du chronométrage :
  /// une course de 90 s estimée à 88 s doit se lire « fermé », pas
  /// « presque fermé ».
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

  /// Reconstruit l'etat. Un mouvement relu du disque est toujours ramené à
  /// `idle` : un volet ne peut pas être en mouvement au lancement de
  /// l'application, puisque aucun mouvement ne survit au relâchement du doigt.
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
      // Sans preuve du contraire, la position est une estimation.
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
