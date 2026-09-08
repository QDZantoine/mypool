import 'dart:async';

import 'package:mypool/data/devices/mqtt_transport.dart';
import 'package:mypool/data/devices/pool_device_driver.dart';

/// Une publication observée, avec son drapeau de rétention.
///
/// Le drapeau est enregistré parce que c'est lui qu'un test doit pouvoir
/// vérifier : une commande retenue par le broker serait relivrée au module et
/// relancerait un mouvement de bâche tout seul.
class PublishedMessage {
  const PublishedMessage(this.topic, this.payload, this.retain);

  final String topic;
  final String payload;
  final bool retain;

  bool get isCommand => topic.contains('/cmd/');

  @override
  String toString() => 'PublishedMessage($topic, $payload, retain: $retain)';
}

/// Broker de test : aucun réseau, tout est piloté à la main.
class FakeMqttTransport implements MqttTransport {
  final List<PublishedMessage> published = <PublishedMessage>[];
  final List<String> subscriptions = <String>[];

  final StreamController<MqttInbound> _messages =
      StreamController<MqttInbound>.broadcast();
  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  bool _connected = false;
  int connectAttempts = 0;

  /// Nombre de tentatives de connexion à faire échouer avant d'accepter.
  int failuresBeforeSuccess = 0;

  /// Fait échouer la prochaine publication avec une exception INATTENDUE,
  /// c'est-à-dire pas une DeviceException : le pilote doit la traduire en
  /// message affichable au lieu de la laisser remonter à l'écran.
  bool throwOnPublish = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<MqttInbound> get messages => _messages.stream;

  @override
  Stream<bool> get connectionChanges => _connection.stream;

  @override
  Future<void> connect() async {
    connectAttempts++;
    if (failuresBeforeSuccess > 0) {
      failuresBeforeSuccess--;
      throw const DeviceException('Impossible de joindre le broker de test.');
    }
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _messages.close();
    await _connection.close();
  }

  @override
  Future<void> subscribe(String topicFilter) async {
    subscriptions.add(topicFilter);
  }

  @override
  Future<void> publish(
    String topic,
    String payload, {
    bool retain = false,
  }) async {
    if (throwOnPublish) {
      // Une Exception, pas une Error : un transport réel lève des
      // SocketException. Les Error signalent des bugs de programmation et ne
      // s'attrapent pas.
      throw Exception('socket fermée');
    }
    published.add(PublishedMessage(topic, payload, retain));
  }

  // --- Pilotage du faux broker ---------------------------------------------

  /// Simule l'arrivée d'un message sur un topic abonné.
  void deliver(String topic, String payload) {
    _messages.add(MqttInbound(topic, payload));
  }

  /// Simule une chute de la liaison.
  void dropConnection() {
    _connected = false;
    _connection.add(false);
  }

  /// Simule un retour de la liaison signalé par le transport.
  void restoreConnection() {
    _connected = true;
    _connection.add(true);
  }

  List<PublishedMessage> get commands =>
      published.where((PublishedMessage m) => m.isCommand).toList();
}
