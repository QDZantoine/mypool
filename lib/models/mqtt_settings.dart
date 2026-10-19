import 'json_tolerant.dart';

class MqttSettings {
  const MqttSettings({
    this.host = defaultHost,
    this.port = defaultPort,
    this.deviceId = '',
    this.username,
    this.password,
  });

  static const String defaultHost = 'broker.hivemq.com';

  static const int defaultPort = 1883;

  static const int minimumDeviceIdLength = 8;

  final String host;
  final int port;
  final String deviceId;
  final String? username;
  final String? password;

  String get topicBase => 'aquacontrol/$deviceId';

  String get topicTelemetry => '$topicBase/state/telemetry';
  String get topicOnline => '$topicBase/state/online';
  String get topicFilterAlert => '$topicBase/state/alert/filter';

  String get topicStateWildcard => '$topicBase/state/#';

  String commandTopic(String leaf) => '$topicBase/cmd/$leaf';

  bool get isUsable =>
      host.trim().isNotEmpty &&
      port > 0 &&
      deviceId.trim().length >= minimumDeviceIdLength;

  bool get isPublicBroker =>
      host.contains('hivemq.com') ||
      host.contains('emqx.io') ||
      host.contains('mosquitto.org');

  MqttSettings copyWith({
    String? host,
    int? port,
    String? deviceId,
    String? username,
    String? password,
  }) {
    return MqttSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      deviceId: deviceId ?? this.deviceId,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'host': host,
      'port': port,
      'deviceId': deviceId,
      'username': username,
      'password': password,
    };
  }

  factory MqttSettings.fromJson(Object? raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return MqttSettings(
      host: readString(json, 'host', defaultHost),

      port: readInt(json, 'port', defaultPort).clamp(1, 65535),
      deviceId: readString(json, 'deviceId', ''),
      username: readNullableString(json, 'username'),
      password: readNullableString(json, 'password'),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MqttSettings &&
        other.host == host &&
        other.port == port &&
        other.deviceId == deviceId &&
        other.username == username &&
        other.password == password;
  }

  @override
  int get hashCode => Object.hash(host, port, deviceId, username, password);

  @override
  String toString() => 'MqttSettings($host:$port, $deviceId)';
}
