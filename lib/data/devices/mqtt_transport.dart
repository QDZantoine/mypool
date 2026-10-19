import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../../models/mqtt_settings.dart';
import 'pool_device_driver.dart';

class MqttInbound {
  const MqttInbound(this.topic, this.payload);

  final String topic;
  final String payload;

  @override
  String toString() => 'MqttInbound($topic, $payload)';
}

abstract class MqttTransport {
  Future<void> connect();

  Future<void> disconnect();

  bool get isConnected;

  Stream<MqttInbound> get messages;

  Stream<bool> get connectionChanges;

  Future<void> subscribe(String topicFilter);

  Future<void> publish(String topic, String payload, {bool retain = false});
}

class MqttClientTransport implements MqttTransport {
  MqttClientTransport({
    required MqttSettings settings,
    MqttServerClient? client,
  }) : _settings = settings,
       _customClient = client,
       _client = client ?? _buildClient(settings) {
    _configureClient(_client);
  }

  final MqttSettings _settings;
  final MqttServerClient? _customClient;
  MqttServerClient _client;

  static MqttServerClient _buildClient(MqttSettings settings) {
    final String clientId =
        'aquacontrol-app-${settings.deviceId}-${DateTime.now().millisecondsSinceEpoch}';
    final MqttServerClient client = MqttServerClient.withPort(
      settings.host,
      clientId,
      settings.port,
    );
    if (settings.port == 8883 || settings.host.contains('hivemq.cloud')) {
      client.secure = true;
      client.onBadCertificate = (dynamic cert) => true;
    }
    client.keepAlivePeriod = 20;
    client.autoReconnect = false;
    return client;
  }

  void _configureClient(MqttServerClient client) {
    client.onDisconnected = _handleDisconnected;
    client.onConnected = _handleConnected;
  }

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
    if (isConnected) {
      return;
    }
    await _updates?.cancel();
    _updates = null;

    if (_customClient == null) {
      try {
        _client.disconnect();
      } catch (_) {}
      _client = _buildClient(_settings);
      _configureClient(_client);
    }

    try {
      await _client.connect(_settings.username, _settings.password);
    } catch (error) {
      try {
        _client.disconnect();
      } catch (_) {}
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

    _subscribeToUpdates();
  }

  void _subscribeToUpdates() {
    if (_updates == null && _client.updates != null) {
      _updates = _client.updates!.listen(
        _handleUpdates,
        onError: (Object error) {
          _handleDisconnected();
        },
      );
    }
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
    _subscribeToUpdates();
    _connection.add(true);
  }

  void _handleDisconnected() {
    unawaited(_updates?.cancel());
    _updates = null;
    _connection.add(false);
  }

  @override
  Future<void> subscribe(String topicFilter) async {
    if (!isConnected) {
      return;
    }
    try {
      _client.subscribe(topicFilter, MqttQos.atLeastOnce);
    } catch (_) {

    }
  }

  @override
  Future<void> publish(
    String topic,
    String payload, {
    bool retain = false,
  }) async {
    try {
      final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder()
        ..addString(payload);
      _client.publishMessage(
        topic,
        MqttQos.atLeastOnce,
        builder.payload!,
        retain: retain,
      );
    } catch (error) {
      throw DeviceException(
        'La commande n’a pas pu être envoyée au module.',
        technicalDetail: '$topic=$payload : $error',
      );
    }
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
