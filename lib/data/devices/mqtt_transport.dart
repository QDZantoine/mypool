import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../../models/mqtt_settings.dart';
import 'pool_device_driver.dart';

/// Un message reçu du broker.
class MqttInbound {
  const MqttInbound(this.topic, this.payload);

  final String topic;
  final String payload;

  @override
  String toString() => 'MqttInbound($topic, $payload)';
}

/// Ce dont le pilote a besoin d'un broker MQTT, et rien de plus.
///
/// Cette abstraction existe pour une raison précise : elle permet de tester
/// tout le pilote — y compris la reconnexion et l'interdiction de rétention
/// sur les commandes — sans broker et sans réseau. La dépendance à
/// `mqtt_client` est confinée à [MqttClientTransport], en dessous.
abstract class MqttTransport {
  Future<void> connect();

  Future<void> disconnect();

  bool get isConnected;

  /// Messages reçus sur les topics abonnés.
  Stream<MqttInbound> get messages;

  /// Passages en ligne / hors ligne de la liaison.
  Stream<bool> get connectionChanges;

  Future<void> subscribe(String topicFilter);

  /// Publie un message.
  ///
  /// `retain` est exposé parce que les topics d'état l'utilisent, mais le
  /// pilote ne le passe JAMAIS à `true` sur un topic de commande.
  Future<void> publish(String topic, String payload, {bool retain = false});
}

/// Transport réel, au-dessus du paquet `mqtt_client`.
///
/// NON COUVERT PAR LES TESTS UNITAIRES : il ne fait rien d'autre que traduire
/// l'API de `mqtt_client`, et l'exercer demanderait un broker. Toute la
/// logique testable a été poussée dans [MqttTransport] et dans le pilote.
class MqttClientTransport implements MqttTransport {
  MqttClientTransport({
    required MqttSettings settings,
    MqttServerClient? client,
  }) : _settings = settings,
       _client =
           client ??
           MqttServerClient.withPort(
             settings.host,
             // Identifiant de session unique : deux clients qui partagent le
             // même identifiant se déconnectent mutuellement en boucle.
             'aquacontrol-app-${settings.deviceId}',
             settings.port,
           ) {
    _client
      // Le keepalive fixe le délai au bout duquel le broker publie le
      // testament du module. 20 s : assez court pour détecter une coupure,
      // assez long pour ne pas battre inutilement.
      ..keepAlivePeriod = 20
      ..autoReconnect =
          false // la reconnexion est orchestrée par le pilote
      ..onDisconnected = _handleDisconnected
      ..onConnected = _handleConnected;
  }

  final MqttSettings _settings;
  final MqttServerClient _client;

  final StreamController<MqttInbound> _messages =
      StreamController<MqttInbound>.broadcast();
  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updates;

  @override
  bool get isConnected =>
      _client.connectionStatus?.state == MqttConnectionState.connected;

  @override
  Stream<MqttInbound> get messages => _messages.stream;

  @override
  Stream<bool> get connectionChanges => _connection.stream;

  @override
  Future<void> connect() async {
    try {
      await _client.connect(_settings.username, _settings.password);
    } on Exception catch (error) {
      _client.disconnect();
      throw DeviceException(
        'Impossible de joindre le broker ${_settings.host}.',
        technicalDetail: '$error',
      );
    }
    if (!isConnected) {
      throw DeviceException(
        'Le broker ${_settings.host} a refusé la connexion.',
        technicalDetail: '${_client.connectionStatus}',
      );
    }
    _updates ??= _client.updates?.listen(_handleUpdates);
  }

  void _handleUpdates(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final MqttReceivedMessage<MqttMessage> event in events) {
      final MqttMessage message = event.payload;
      if (message is! MqttPublishMessage) {
        continue;
      }
      final String payload = MqttPublishPayload.bytesToStringAsString(
        message.payload.message,
      );
      _messages.add(MqttInbound(event.topic, payload));
    }
  }

  void _handleConnected() {
    _connection.add(true);
  }

  void _handleDisconnected() {
    _connection.add(false);
  }

  @override
  Future<void> subscribe(String topicFilter) async {
    // Qualité de service 1 dans les deux sens : une télémétrie perdue est un
    // état figé à l'écran (addendum § 3.2).
    _client.subscribe(topicFilter, MqttQos.atLeastOnce);
  }

  @override
  Future<void> publish(
    String topic,
    String payload, {
    bool retain = false,
  }) async {
    final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder()
      ..addString(payload);
    _client.publishMessage(
      topic,
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: retain,
    );
  }

  @override
  Future<void> disconnect() async {
    await _updates?.cancel();
    _updates = null;
    _client.disconnect();
    await _messages.close();
    await _connection.close();
  }
}
