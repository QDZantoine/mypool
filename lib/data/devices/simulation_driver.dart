import 'dart:math' as math;

import '../../models/filtration_schedule.dart';
import 'pool_device_driver.dart';

/// Pilote de simulation : aucun accès réseau, aucun matériel.
///
/// Sert aux tests unitaires et au développement hors ligne, et c'est le pilote
/// par défaut de l'application : elle doit être utilisable avant tout
/// appairage.
///
/// Point de conception essentiel : une impulsion ne retombe PAS grâce à un
/// minuteur qui rappellerait une méthode. Elle retombe parce que
/// [relayState] compare l'heure courante à la fin de la fenêtre d'impulsion.
/// Il n'existe donc aucun chemin de code capable de « rater » l'arrêt, ce qui
/// est exactement ce que la règle de sécurité n° 2 exige du matériel réel.
class SimulationDriver implements PoolDeviceDriver {
  SimulationDriver({
    DateTime Function()? clock,
    this.coverTravel = const Duration(seconds: 90),
    this.latency = const Duration(milliseconds: 20),
    this.hasLimitSwitches = false,
  }) : _clock = clock ?? DateTime.now;

  /// Horloge injectable : les tests avancent le temps à la main plutôt que
  /// d'attendre réellement.
  final DateTime Function() _clock;

  /// Durée d'une course complète du volet, reprise de la configuration.
  final Duration coverTravel;

  /// Latence simulée, rendue par [ping].
  final Duration latency;

  /// La plupart des coffrets ne remontent aucune fin de course. Passer à
  /// `true` permet de développer le cas, plus rare, où l'installation en a.
  final bool hasLimitSwitches;

  /// Fin de la fenêtre d'impulsion en cours, par canal.
  final Map<DeviceChannel, DateTime> _pulseUntil = <DeviceChannel, DateTime>{};

  /// État des relais forcés, par canal.
  final Map<DeviceChannel, bool> _latched = <DeviceChannel, bool>{};

  /// Position estimée du volet, de 0 (fermé) à 1 (ouvert).
  double _openRatio = 0.0;

  /// Instant jusqu'auquel le mouvement a déjà été intégré.
  DateTime? _integratedUntil;

  FiltrationSchedule? _schedule;

  bool _online = true;

  bool _disposed = false;

  /// Nombre d'impulsions reçues, tous canaux confondus.
  ///
  /// Sert aux tests du contrôleur de volet : c'est ce compteur qui prouve
  /// qu'aucune commande ne part sans consentement.
  int pulseCount = 0;

  // ---------------------------------------------------------------------------
  // Pilotage de la simulation, réservé aux tests et au mode démonstration.
  // ---------------------------------------------------------------------------

  /// Coupe ou rétablit la liaison simulée.
  ///
  /// Permet de rejouer sans matériel les essais de l'addendum § 4.3 : broker
  /// injoignable, module hors ligne.
  void setOnline(bool online) {
    _online = online;
  }

  bool get isOnline => _online;

  /// Position estimée du volet, après intégration du temps écoulé.
  double get coverOpenRatio {
    _integrate();
    return _openRatio;
  }

  /// Planning écrit dans le module simulé, ou `null` s'il a été effacé.
  FiltrationSchedule? get storedSchedule => _schedule;

  /// Recale la position déclarée, comme la commande de calibration du banc
  /// d'essai (addendum § 3.2).
  void calibrateCover({required bool open}) {
    _integrate();
    _openRatio = open ? 1.0 : 0.0;
  }

  // ---------------------------------------------------------------------------
  // Intégration du mouvement
  // ---------------------------------------------------------------------------

  /// Avance la position du volet du temps pendant lequel un contact était
  /// fermé depuis la dernière intégration.
  ///
  /// Appelée au début de chaque opération : la position n'est jamais calculée
  /// en avance, seulement rattrapée. Si les deux contacts sont fermés en même
  /// temps — ce qu'aucun chemin normal ne produit — les mouvements s'annulent,
  /// ce qui est aussi le comportement d'un coffret câblé.
  void _integrate() {
    final DateTime now = _clock();
    final DateTime from = _integratedUntil ?? now;
    _integratedUntil = now;
    if (!now.isAfter(from)) {
      return;
    }

    final int travelMs = coverTravel.inMilliseconds;
    if (travelMs <= 0) {
      return;
    }

    double delta = 0.0;
    for (final DeviceChannel channel in <DeviceChannel>[
      DeviceChannel.coverOpen,
      DeviceChannel.coverClose,
    ]) {
      final DateTime? until = _pulseUntil[channel];
      if (until == null) {
        continue;
      }
      // Seule la portion de l'intervalle réellement couverte par l'impulsion
      // fait bouger le volet.
      final DateTime end = until.isBefore(now) ? until : now;
      if (!end.isAfter(from)) {
        continue;
      }
      final double moved = end.difference(from).inMilliseconds / travelMs;
      delta += channel == DeviceChannel.coverOpen ? moved : -moved;
    }

    _openRatio = math.min(1.0, math.max(0.0, _openRatio + delta));
  }

  void _checkUsable() {
    if (_disposed) {
      throw const DeviceException(
        'La liaison avec le module a été fermée.',
        technicalDetail: 'SimulationDriver déjà libéré',
      );
    }
    if (!_online) {
      throw const DeviceException(
        'Le module ne répond pas. Vérifiez qu’il est alimenté et connecté.',
        technicalDetail: 'simulation hors ligne',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // PoolDeviceDriver
  // ---------------------------------------------------------------------------

  @override
  Future<void> pulse(DeviceChannel channel, {required Duration autoOff}) async {
    // La garde de sécurité passe avant la vérification de liaison : une
    // temporisation illégale est un défaut de programmation, pas une panne.
    CoverSafety.checkCoverAutoOff(channel, autoOff);
    _checkUsable();
    _integrate();

    // Un ordre en sens inverse annule le sens précédent : c'est le
    // comportement d'un coffret dont les deux contacts sont mutuellement
    // verrouillés.
    if (channel == DeviceChannel.coverOpen) {
      _pulseUntil.remove(DeviceChannel.coverClose);
    } else if (channel == DeviceChannel.coverClose) {
      _pulseUntil.remove(DeviceChannel.coverOpen);
    }

    _pulseUntil[channel] = _clock().add(autoOff);
    pulseCount++;
  }

  @override
  Future<void> setRelay(DeviceChannel channel, {required bool on}) async {
    if (channel == DeviceChannel.coverOpen ||
        channel == DeviceChannel.coverClose) {
      // Un canal de volet enclenché en continu n'aurait plus de retombée
      // automatique : le volet bougerait jusqu'en fin de course sans personne.
      throw DeviceException(
        'Un volet ne se commande jamais en marche continue.',
        technicalDetail: 'setRelay refusé sur ${channel.name}',
      );
    }
    _checkUsable();
    _latched[channel] = on;
  }

  @override
  Future<bool> relayState(DeviceChannel channel) async {
    _checkUsable();
    _integrate();
    final DateTime? until = _pulseUntil[channel];
    if (until != null) {
      // C'est ici que l'impulsion retombe : une comparaison d'heures, pas un
      // ordre d'arrêt.
      if (_clock().isBefore(until)) {
        return true;
      }
      _pulseUntil.remove(channel);
    }
    return _latched[channel] ?? false;
  }

  @override
  Future<double?> relayPower(DeviceChannel channel) async {
    _checkUsable();
    final bool on = await relayState(channel);
    if (!on) {
      return 0.0;
    }
    switch (channel) {
      // Ordres de grandeur d'une installation domestique, pour que les écrans
      // affichent des valeurs plausibles en mode simulation.
      case DeviceChannel.pump:
        return 450.0; // pompe de 3/4 CV
      case DeviceChannel.heater:
        return 3000.0; // réchauffeur électrique
      case DeviceChannel.coverOpen:
      case DeviceChannel.coverClose:
        return 120.0; // moteur tubulaire de volet
    }
  }

  @override
  Future<bool?> inputState(DeviceInput input) async {
    _checkUsable();
    if (!hasLimitSwitches) {
      // Pas de capteur : la position reste une estimation, et l'interface doit
      // l'afficher comme telle.
      return null;
    }
    _integrate();
    switch (input) {
      case DeviceInput.coverOpenedLimit:
        return _openRatio >= 0.98;
      case DeviceInput.coverClosedLimit:
        return _openRatio <= 0.02;
    }
  }

  @override
  Future<Duration> ping() async {
    _checkUsable();
    return latency;
  }

  @override
  Future<void> pushFiltrationSchedule(FiltrationSchedule schedule) async {
    _checkUsable();
    _schedule = schedule;
  }

  @override
  Future<void> clearFiltrationSchedule() async {
    _checkUsable();
    _schedule = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _pulseUntil.clear();
  }
}
