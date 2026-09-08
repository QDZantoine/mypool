import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/devices/pool_device_driver.dart';
import '../models/cover_state.dart';
import '../models/pool_config.dart';

/// Fabrique de minuteur périodique, injectable pour les tests.
///
/// Le contrôleur ne crée jamais `Timer.periodic` lui-même : les tests
/// fournissent un faux minuteur et déclenchent les battements à la main, ce
/// qui permet de vérifier la mécanique de sécurité sans attendre réellement.
typedef PeriodicTimerFactory = Timer Function(
  Duration interval,
  void Function(Timer timer) onTick,
);

/// Raison pour laquelle une commande de volet n'a pas été exécutée.
enum CoverRefusal {
  /// Aucun refus.
  none,

  /// L'avertissement de sécurité n'a pas été accepté (règle n° 4).
  consentMissing,

  /// L'installation déclarée n'a pas de volet motorisé.
  noMotorisedCover,

  /// Le module n'a pas accepté la commande.
  deviceError,
}

/// État exposé par le contrôleur de volet.
///
/// Enveloppe le modèle [CoverState] avec ce qui ne se persiste pas : la raison
/// du dernier refus et le message d'erreur affichable. Ces deux informations
/// n'ont de sens que pendant la session en cours.
class CoverStatus {
  const CoverStatus({
    this.cover = CoverState.unknownState,
    this.refusal = CoverRefusal.none,
    this.errorMessage,
  });

  final CoverState cover;
  final CoverRefusal refusal;

  /// Message en français, directement affichable. Jamais une trace technique.
  final String? errorMessage;

  bool get isMoving => cover.isMoving;

  CoverStatus copyWith({
    CoverState? cover,
    CoverRefusal? refusal,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CoverStatus(
      cover: cover ?? this.cover,
      refusal: refusal ?? this.refusal,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  String toString() =>
      'CoverStatus(${cover.position.name}, '
      '${cover.motion.name}, ${refusal.name})';
}

/// Pilotage du volet, à doigt maintenu.
///
/// Les six règles de sécurité du projet se lisent directement dans ce fichier :
///
/// 1. Aucun mouvement sans doigt maintenu : [pressOpen] et [pressClose]
///    n'engagent qu'une republication périodique, et [release] la coupe.
/// 2. La temporisation d'arrêt vit dans le matériel : chaque impulsion porte
///    [CoverSafety.holdTimeout], et [release] n'envoie AUCUN ordre d'arrêt.
///    L'arrêt n'est pas commandé, il est constaté.
/// 3. Aucune fermeture programmée : il n'existe pas de méthode qui prenne une
///    position cible ou une heure.
/// 4. Sans consentement, aucune commande ne part — pas même la première.
/// 5. Le module ferme un contact en parallèle des boutons du coffret : le
///    contrôleur n'a aucune notion de fin de course qu'il devrait respecter
///    lui-même.
/// 6. La position est une estimation, sauf si le module remonte une vraie fin
///    de course : [CoverState.isEstimated] le dit.
class CoverController extends StateNotifier<CoverStatus> {
  CoverController({
    required this._driver,
    required this._config,
    DateTime Function()? clock,
    PeriodicTimerFactory? timerFactory,
  }) : _clock = clock ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.periodic,
       super(const CoverStatus());

  final PoolDeviceDriver _driver;

  /// Lu à chaque commande, et non copié au constructeur : le consentement et
  /// la durée de course peuvent changer dans les réglages pendant la session.
  final PoolConfig Function() _config;

  final DateTime Function() _clock;
  final PeriodicTimerFactory _timerFactory;

  Timer? _holdTimer;

  /// Instant de la dernière intégration de position.
  DateTime? _movingSince;

  /// Sens du mouvement en cours, `null` à l'arrêt.
  CoverMotion _direction = CoverMotion.idle;

  /// Le doigt est-il posé ?
  bool get isHeld => _holdTimer != null;

  /// Demande une ouverture. Rend `true` si la commande est partie.
  Future<bool> pressOpen() => _press(CoverMotion.opening);

  /// Demande une fermeture. Rend `true` si la commande est partie.
  Future<bool> pressClose() => _press(CoverMotion.closing);

  Future<bool> _press(CoverMotion direction) async {
    final PoolConfig config = _config();

    // Règle n° 4 : le consentement est vérifié AVANT tout contact avec le
    // module. Aucune impulsion, même unique, ne part sans lui.
    if (!config.safetyConsentGiven) {
      state = state.copyWith(refusal: CoverRefusal.consentMissing);
      return false;
    }
    if (!config.hasMotorisedCover) {
      state = state.copyWith(refusal: CoverRefusal.noMotorisedCover);
      return false;
    }

    // Un ordre en sens inverse pendant un mouvement change simplement de sens :
    // on coupe la republication en cours avant d'engager la nouvelle.
    if (_direction != CoverMotion.idle && _direction != direction) {
      _integrate();
      _stopRepeating();
    }

    _direction = direction;
    final bool sent = await _sendPulse();
    if (!sent) {
      return false;
    }

    _movingSince = _clock();
    state = state.copyWith(
      cover: state.cover.copyWith(motion: direction, lastMovedAt: _clock()),
      refusal: CoverRefusal.none,
      clearError: true,
    );

    // La republication ne démarre qu'après une première impulsion acceptée.
    _holdTimer ??= _timerFactory(
      CoverSafety.holdRepeatInterval,
      (Timer _) => unawaited(_tick()),
    );
    return true;
  }

  /// Le doigt se relève.
  ///
  /// Coupe la republication. Aucun ordre n'est envoyé au module : le mouvement
  /// s'arrête parce que le délai de garde matériel expire, et cet arrêt
  /// fonctionne aussi quand l'application est tuée, le réseau coupé ou le
  /// téléphone verrouillé. Envoyer un ordre d'arrêt ici donnerait l'illusion
  /// que la sécurité en dépend.
  Future<void> release() async {
    if (_direction == CoverMotion.idle && _holdTimer == null) {
      return;
    }
    // La répétition est coupée AVANT toute mise à jour d'état : c'est elle
    // qui porte la sécurité, et elle ne doit pas dépendre du bon déroulement
    // d'un rafraîchissement d'affichage.
    _stopRepeating();
    _integrateFrom(_movingSinceBeforeStop);
    _direction = CoverMotion.idle;
    state = state.copyWith(
      cover: state.cover.copyWith(motion: CoverMotion.idle),
    );
  }

  /// Un battement de la republication.
  Future<void> _tick() async {
    if (_direction == CoverMotion.idle) {
      return;
    }
    _integrate();

    // Une vraie fin de course, quand le module en a une, arrête le mouvement
    // et rend la position certaine.
    final bool reachedLimit = await _checkLimitSwitch();
    if (reachedLimit) {
      await release();
      return;
    }

    await _sendPulse();
  }

  /// Envoie une impulsion sur le canal correspondant au sens en cours.
  ///
  /// Rend `false` et arrête le mouvement en cas d'erreur : cesser de republier
  /// est la bonne réaction à une panne de liaison, puisque le matériel
  /// s'arrêtera de lui-même en moins de deux secondes.
  Future<bool> _sendPulse() async {
    final DeviceChannel channel = _direction == CoverMotion.opening
        ? DeviceChannel.coverOpen
        : DeviceChannel.coverClose;
    try {
      await _driver.pulse(channel, autoOff: CoverSafety.holdTimeout);
      return true;
    } on DeviceException catch (error) {
      _stopRepeating();
      _direction = CoverMotion.idle;
      state = state.copyWith(
        cover: state.cover.copyWith(motion: CoverMotion.idle),
        refusal: CoverRefusal.deviceError,
        errorMessage: error.message,
      );
      return false;
    }
  }

  Future<bool> _checkLimitSwitch() async {
    final DeviceInput input = _direction == CoverMotion.opening
        ? DeviceInput.coverOpenedLimit
        : DeviceInput.coverClosedLimit;
    try {
      final bool? reached = await _driver.inputState(input);
      if (reached == null) {
        // Pas de capteur : on continue, la position reste une estimation.
        return false;
      }
      if (reached) {
        state = state.copyWith(
          cover: state.cover.copyWith(
            openRatio: _direction == CoverMotion.opening ? 1.0 : 0.0,
            position: _direction == CoverMotion.opening
                ? CoverPosition.open
                : CoverPosition.closed,
            isEstimated: false,
          ),
        );
      }
      return reached;
    } on DeviceException {
      // Une entrée illisible ne doit pas interrompre le mouvement : le doigt
      // de l'utilisateur reste l'autorité.
      return false;
    }
  }

  /// Avance l'estimation de position du temps écoulé depuis le dernier calcul.
  ///
  /// N'intègre que le temps de doigt posé, et ignore donc les ~1,8 s pendant
  /// lesquelles le matériel continue seul après le relâchement. L'erreur est
  /// volontairement de ce côté : elle fait annoncer un volet MOINS fermé qu'il
  /// ne l'est, jamais l'inverse.
  void _integrate() => _integrateFrom(_movingSince);

  void _integrateFrom(DateTime? since) {
    if (since == null || _direction == CoverMotion.idle) {
      return;
    }
    final DateTime now = _clock();
    _movingSince = now;

    final double travelSeconds = _config().coverTravelSeconds;
    if (travelSeconds <= 0) {
      return;
    }
    final double elapsed = now.difference(since).inMilliseconds / 1000.0;
    if (elapsed <= 0) {
      return;
    }

    final double delta = elapsed / travelSeconds;
    double ratio =
        state.cover.openRatio +
        (_direction == CoverMotion.opening ? delta : -delta);
    ratio = ratio.clamp(0.0, 1.0);

    state = state.copyWith(
      cover: state.cover.copyWith(
        openRatio: ratio,
        position: CoverState.positionFromRatio(ratio),
        lastMovedAt: now,
      ),
    );
  }

  /// Instant de dernière intégration, conservé pendant l'arrêt.
  ///
  /// [_stopRepeating] efface [_movingSince] parce que plus rien ne bouge ;
  /// mais le dernier fragment de mouvement doit encore être intégré, d'où
  /// cette copie.
  DateTime? _movingSinceBeforeStop;

  void _stopRepeating() {
    _movingSinceBeforeStop = _movingSince;
    _holdTimer?.cancel();
    _holdTimer = null;
    _movingSince = null;
  }

  /// Recale la position déclarée, sur affirmation de l'utilisateur.
  ///
  /// Ce n'est pas une mesure : la position reste marquée comme estimée, parce
  /// que c'est un humain qui a dit « il est fermé », pas un capteur.
  void declarePosition({required bool open}) {
    if (_direction != CoverMotion.idle) {
      return;
    }
    state = state.copyWith(
      cover: state.cover.copyWith(
        openRatio: open ? 1.0 : 0.0,
        position: open ? CoverPosition.open : CoverPosition.closed,
        isEstimated: true,
        lastMovedAt: _clock(),
      ),
    );
  }

  /// Relit l'état de la pompe sur le module, pour l'afficher.
  ///
  /// Ne touche pas au volet : un rafraîchissement d'affichage ne doit jamais
  /// pouvoir déclencher ou interrompre un mouvement.
  Future<void> refreshPump() async {
    try {
      final bool on = await _driver.relayState(DeviceChannel.pump);
      final double? power = await _driver.relayPower(DeviceChannel.pump);
      state = state.copyWith(
        cover: state.cover.copyWith(
          pump: on ? PumpState.on : PumpState.off,
          pumpPowerW: power,
        ),
        clearError: true,
      );
    } on DeviceException catch (error) {
      state = state.copyWith(
        cover: state.cover.copyWith(pump: PumpState.unknown),
        errorMessage: error.message,
      );
    }
  }

  @override
  void dispose() {
    _stopRepeating();
    super.dispose();
  }
}
