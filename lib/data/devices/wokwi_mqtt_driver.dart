import 'dart:async';
import 'dart:convert';

import '../../models/filtration_schedule.dart';
import '../../models/mqtt_settings.dart';
import 'mqtt_transport.dart';
import 'pool_device_driver.dart';
import 'telemetry.dart';

/// Pilote du banc d'essai ESP32, en MQTT (addendum § 3).
///
/// Écrit contre le contrat du § 3 de l'addendum : commandes textuelles courtes
/// sur `.../cmd/<leaf>`, état en JSON retenu sur `.../state/telemetry`,
/// présence sur `.../state/online` avec testament MQTT.
///
/// Deux principes de sécurité gouvernent ce fichier :
///
/// 1. **La temporisation d'arrêt n'est jamais envoyée.** [pulse] publie
///    « open » ou « close » et ignore délibérément son paramètre `autoOff` :
///    le délai de garde vit dans le firmware. Voir le commentaire de [pulse].
/// 2. **Aucune commande n'est publiée en rétention.** Un « open » retenu par
///    le broker serait relivré au module à sa prochaine reconnexion et
///    relancerait un mouvement de bâche sans personne devant la piscine.
class WokwiMqttDriver implements PoolDeviceDriver {
  WokwiMqttDriver({
    required this._settings,
    required this._transport,
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
    this.telemetryTimeout = const Duration(seconds: 6),
    this.telemetryFreshness = const Duration(seconds: 10),
  }) : _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  /// Feuilles de topic de commande du contrat § 3.2.
  static const String cmdCover = 'cover';
  static const String cmdCoverCalibrate = 'cover-calibrate';
  static const String cmdPump = 'pump';
  static const String cmdHeater = 'heater';
  static const String cmdSetpoint = 'setpoint';
  static const String cmdFilterReset = 'filter-reset';
  static const String cmdPing = 'ping';

  /// Délais de reconnexion successifs.
  ///
  /// Progressifs pour ne pas marteler un broker en panne, plafonnés à 30 s
  /// pour que le retour en ligne reste rapide à l'échelle d'un utilisateur au
  /// bord du bassin.
  static const List<Duration> reconnectBackoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  final MqttSettings _settings;
  final MqttTransport _transport;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;

  /// Délai maximal d'attente d'une réponse à [ping].
  final Duration telemetryTimeout;

  /// Au-delà de cet âge, la dernière télémétrie n'est plus considérée comme
  /// représentative de l'état courant.
  ///
  /// Le module publie toutes les 2 s : 10 s laissent passer quatre trames
  /// perdues avant de déclarer l'état périmé.
  final Duration telemetryFreshness;

  final StreamController<PoolTelemetry> _telemetry =
      StreamController<PoolTelemetry>.broadcast();
  final StreamController<bool> _online = StreamController<bool>.broadcast();

  StreamSubscription<MqttInbound>? _messages;
  StreamSubscription<bool>? _connection;

  PoolTelemetry? _lastTelemetry;
  bool _moduleOnline = false;
  bool _filterAlert = false;
  bool _started = false;
  bool _disposed = false;
  int _reconnectAttempt = 0;

  /// Dernière télémétrie reçue, quel que soit son âge.
  PoolTelemetry? get lastTelemetry => _lastTelemetry;

  /// Flux des trames reçues, pour le tableau de bord.
  Stream<PoolTelemetry> get telemetryStream => _telemetry.stream;

  /// Flux de présence du MODULE, distinct de celui de la liaison au broker.
  ///
  /// La distinction compte : le téléphone peut être connecté au broker alors
  /// que l'ESP32 est débranché. C'est le testament MQTT qui le dit.
  Stream<bool> get moduleOnlineStream => _online.stream;

  bool get isModuleOnline => _moduleOnline;

  bool get filterAlert => _filterAlert;

  /// La dernière télémétrie est-elle assez récente pour être affichée ?
  bool get hasFreshTelemetry {
    final PoolTelemetry? last = _lastTelemetry;
    if (last == null) {
      return false;
    }
    return _clock().difference(last.receivedAt) <= telemetryFreshness;
  }

  // ---------------------------------------------------------------------------
  // Cycle de vie
  // ---------------------------------------------------------------------------

  /// Ouvre la liaison et s'abonne aux topics d'état.
  Future<void> start() async {
    if (_disposed) {
      throw const DeviceException('La liaison au module a été fermée.');
    }
    if (!_settings.isUsable) {
      throw DeviceException(
        'Réglages de liaison incomplets : renseignez l’adresse du broker et '
        'un identifiant d’installation d’au moins '
        '${MqttSettings.minimumDeviceIdLength} caractères.',
        technicalDetail: 'settings=$_settings',
      );
    }

    _messages ??= _transport.messages.listen(_handleMessage);
    _connection ??= _transport.connectionChanges.listen(
      _handleConnectionChange,
    );

    await _transport.connect();
    await _subscribeState();
    _started = true;
    _reconnectAttempt = 0;
  }

  Future<void> _subscribeState() async {
    // Un seul filtre couvre télémétrie, présence et alerte filtre.
    await _transport.subscribe(_settings.topicStateWildcard);
  }

  void _handleConnectionChange(bool connected) {
    if (connected) {
      _reconnectAttempt = 0;
      // L'abonnement ne survit pas à une déconnexion : il faut le rétablir.
      unawaited(_subscribeState());
      return;
    }

    // La liaison au broker est tombée : le module n'est plus joignable, et
    // l'état affiché doit le dire au lieu de rester figé.
    _setModuleOnline(false);
    if (_started && !_disposed) {
      unawaited(_reconnect());
    }
  }

  /// Reconnexion avec délais progressifs.
  Future<void> _reconnect() async {
    while (_started && !_disposed && !_transport.isConnected) {
      final Duration wait =
          reconnectBackoff[_reconnectAttempt.clamp(
            0,
            reconnectBackoff.length - 1,
          )];
      _reconnectAttempt++;
      await _delay(wait);
      if (_disposed || !_started) {
        return;
      }
      try {
        await _transport.connect();
        await _subscribeState();
        _reconnectAttempt = 0;
        return;
      } on DeviceException {
        // Broker toujours injoignable : on retente, plus lentement.
        continue;
      }
    }
  }

  void _handleMessage(MqttInbound message) {
    if (message.topic == _settings.topicTelemetry) {
      _handleTelemetry(message.payload);
      return;
    }
    if (message.topic == _settings.topicOnline) {
      // « 1 » à la connexion du module, « 0 » via son testament MQTT.
      _setModuleOnline(message.payload.trim() == '1');
      return;
    }
    if (message.topic == _settings.topicFilterAlert) {
      _filterAlert = message.payload.trim() == '1';
    }
  }

  void _handleTelemetry(String payload) {
    if (payload.trim().isEmpty) {
      // Effacement de rétention, ou trame vide : rien à décoder.
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      // Une trame illisible ne doit pas éteindre le flux : sur un broker
      // public, n'importe qui peut publier n'importe quoi sur ce topic.
      return;
    }

    // Un JSON valide n'est pas forcément une trame : `42` ou `"bonjour"` se
    // décodent sans erreur, et se transformeraient en trame vide qui
    // ÉCRASERAIT le dernier état connu. Mieux vaut garder l'état précédent,
    // même vieillissant, que l'effacer sur une publication parasite.
    if (decoded is! Map || decoded.isEmpty) {
      return;
    }

    final PoolTelemetry telemetry = PoolTelemetry.fromJson(
      decoded,
      receivedAt: _clock(),
    );
    _lastTelemetry = telemetry;
    _filterAlert = telemetry.filterAlert;
    // Recevoir une trame prouve que le module parle.
    _setModuleOnline(true);
    if (!_telemetry.isClosed) {
      _telemetry.add(telemetry);
    }
  }

  void _setModuleOnline(bool online) {
    if (_moduleOnline == online) {
      return;
    }
    _moduleOnline = online;
    if (!_online.isClosed) {
      _online.add(online);
    }
  }

  // ---------------------------------------------------------------------------
  // Publication de commandes
  // ---------------------------------------------------------------------------

  /// Publie une commande.
  ///
  /// `retain` n'est pas un paramètre : une commande n'est JAMAIS retenue. Un
  /// ordre de bâche resté sur le broker serait relivré au module à sa
  /// prochaine connexion et relancerait un mouvement tout seul.
  Future<void> _publishCommand(String leaf, String payload) async {
    _checkUsable();
    try {
      await _transport.publish(_settings.commandTopic(leaf), payload);
    } on DeviceException {
      rethrow;
    } on Exception catch (error) {
      throw DeviceException(
        'La commande n’a pas pu être envoyée au module.',
        technicalDetail: '$leaf=$payload : $error',
      );
    }
  }

  void _checkUsable() {
    if (_disposed) {
      throw const DeviceException('La liaison au module a été fermée.');
    }
    if (!_transport.isConnected) {
      throw DeviceException(
        'Pas de liaison avec le broker ${_settings.host}.',
        technicalDetail: 'transport déconnecté',
      );
    }
  }

  /// Dernière télémétrie, si elle est assez fraîche pour faire foi.
  PoolTelemetry _requireFreshTelemetry() {
    final PoolTelemetry? last = _lastTelemetry;
    if (last == null) {
      throw const DeviceException(
        'Le module n’a pas encore transmis son état.',
        technicalDetail: 'aucune télémétrie reçue',
      );
    }
    if (!hasFreshTelemetry) {
      throw DeviceException(
        'L’état du module date de plus de '
        '${telemetryFreshness.inSeconds} secondes.',
        technicalDetail: 'télémétrie reçue à ${last.receivedAt}',
      );
    }
    return last;
  }

  // ---------------------------------------------------------------------------
  // PoolDeviceDriver
  // ---------------------------------------------------------------------------

  @override
  Future<void> pulse(DeviceChannel channel, {required Duration autoOff}) async {
    // La garde de plafond s'applique quand même : elle vérifie que l'appelant
    // demande bien une temporisation courte, ce qui reste une information
    // utile même si la valeur n'est pas transmise.
    CoverSafety.checkCoverAutoOff(channel, autoOff);

    switch (channel) {
      case DeviceChannel.coverOpen:
      case DeviceChannel.coverClose:
        // `autoOff` N'EST PAS ENVOYÉ, et ce n'est pas un oubli : le délai de
        // garde vit dans le firmware, qui arrête le mouvement de lui-même
        // 1 800 ms après le dernier message reçu. Transmettre la
        // temporisation ferait dépendre l'arrêt d'un ordre passé par le
        // réseau, ce qui n'est pas une sécurité (addendum § 4.1).
        await _publishCommand(
          cmdCover,
          channel == DeviceChannel.coverOpen ? 'open' : 'close',
        );
      case DeviceChannel.pump:
      case DeviceChannel.heater:
        // Le contrat § 3.2 n'a pas d'impulsion temporisée pour la pompe : une
        // impulsion sur la pompe n'a pas de sens sur ce montage.
        throw DeviceException(
          'Ce module ne sait pas commander ${channel.name} par impulsion.',
          technicalDetail: 'pulse non supporté sur ${channel.name}',
        );
    }
  }

  @override
  Future<void> setRelay(DeviceChannel channel, {required bool on}) async {
    switch (channel) {
      case DeviceChannel.pump:
        await _publishCommand(cmdPump, on ? 'on' : 'off');
      case DeviceChannel.heater:
        await _publishCommand(cmdHeater, on ? 'on' : 'off');
      case DeviceChannel.coverOpen:
      case DeviceChannel.coverClose:
        // Un canal de bâche enclenché en continu n'aurait plus de retombée
        // automatique. Le contrat § 3.2 ne l'expose délibérément pas.
        throw DeviceException(
          'Un volet ne se commande jamais en marche continue.',
          technicalDetail: 'setRelay refusé sur ${channel.name}',
        );
    }
  }

  @override
  Future<bool> relayState(DeviceChannel channel) async {
    // Aucune requête réseau : l'état vient de la dernière télémétrie reçue.
    final PoolTelemetry telemetry = _requireFreshTelemetry();
    switch (channel) {
      case DeviceChannel.pump:
        return telemetry.pumpOn ?? false;
      case DeviceChannel.heater:
        return telemetry.heaterOn ?? false;
      case DeviceChannel.coverOpen:
        return telemetry.coverMotion == TelemetryMotion.opening;
      case DeviceChannel.coverClose:
        return telemetry.coverMotion == TelemetryMotion.closing;
    }
  }

  @override
  Future<double?> relayPower(DeviceChannel channel) async {
    // Le montage n'a pas de mesure de puissance. `null` le dit, plutôt qu'un
    // zéro qui passerait pour une mesure d'un moteur à l'arrêt.
    _requireFreshTelemetry();
    return null;
  }

  @override
  Future<bool?> inputState(DeviceInput input) async {
    // Le firmware du banc d'essai borne la position lui-même et publie
    // `estimated: true` : il n'a pas de fin de course à remonter. Le `null`
    // fait afficher la position comme une estimation (règle n° 6).
    final PoolTelemetry telemetry = _requireFreshTelemetry();
    if (telemetry.coverEstimated) {
      return null;
    }
    switch (input) {
      case DeviceInput.coverOpenedLimit:
        return (telemetry.coverPosition ?? 0.0) >= 0.98;
      case DeviceInput.coverClosedLimit:
        return (telemetry.coverPosition ?? 0.0) <= 0.02;
    }
  }

  @override
  Future<Duration> ping() async {
    final DateTime sentAt = _clock();
    // Le firmware republie sa télémétrie immédiatement sur ce topic.
    await _publishCommand(cmdPing, '1');

    // On attend une trame POSTÉRIEURE à la demande : une trame déjà reçue,
    // même récente, ne prouverait pas que la liaison fonctionne maintenant.
    try {
      final PoolTelemetry answer = await _telemetry.stream
          .firstWhere((PoolTelemetry t) => !t.receivedAt.isBefore(sentAt))
          .timeout(telemetryTimeout);
      return answer.receivedAt.difference(sentAt);
    } on TimeoutException {
      throw DeviceException(
        'Le module n’a pas répondu en '
        '${telemetryTimeout.inSeconds} secondes.',
        technicalDetail: 'aucune télémétrie après ping',
      );
    }
  }

  @override
  Future<void> pushFiltrationSchedule(FiltrationSchedule schedule) async {
    // Limite assumée du banc d'essai (addendum § 8.1) : le firmware n'embarque
    // ni horloge NTP ni planning en mémoire non volatile. Lever une erreur
    // explicite vaut mieux que faire croire que le planning est écrit dans le
    // matériel : c'est justement l'exigence « la piscine filtre téléphone
    // éteint » qui serait silencieusement perdue.
    throw const DeviceException(
      'Ce module ne sait pas mémoriser un planning de filtration : en liaison '
      'MQTT, la filtration est commandée par l’application, et s’arrête donc '
      'si le téléphone est éteint.',
      technicalDetail: 'pushFiltrationSchedule non supporté (addendum § 8.1)',
    );
  }

  @override
  Future<void> clearFiltrationSchedule() async {
    // Aucun planning n'a jamais été écrit : effacer n'a rien à faire, et
    // échouer ici empêcherait un changement de matériel de se terminer.
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _started = false;
    await _messages?.cancel();
    await _connection?.cancel();
    _messages = null;
    _connection = null;
    await _transport.disconnect();
    await _telemetry.close();
    await _online.close();
  }
}
