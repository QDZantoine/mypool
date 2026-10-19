import 'dart:async';

import 'package:mypool/data/devices/mqtt_transport.dart';
import 'package:mypool/data/devices/pool_device_driver.dart';

class PublishedMessage {
  const PublishedMessage(this.topic, this.payload, this.retain);

  final String topic;
  final String payload;
  final bool retain;

  bool get isCommand => topic.contains('/cmd/');

  @override
  String toString() => 'PublishedMessage($topic, $payload, retain: $retain)';
}

class FakeMqttTransport implements MqttTransport {
  final List<PublishedMessage> published = <PublishedMessage>[];
  final List<String> subscriptions = <String>[];

  final StreamController<MqttInbound> _messages =
      StreamController<MqttInbound>.broadcast();
  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  bool _connected = false;
  int connectAttempts = 0;

  int failuresBeforeSuccess = 0;

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

      throw Exception('socket fermée');
    }
    published.add(PublishedMessage(topic, payload, retain));
  }

  void deliver(String topic, String payload) {
    _messages.add(MqttInbound(topic, payload));
  }

  void dropConnection() {
    _connected = false;
    _connection.add(false);
  }

  void restoreConnection() {
    _connected = true;
    _connection.add(true);
  }

  List<PublishedMessage> get commands =>
      published.where((PublishedMessage m) => m.isCommand).toList();
}
