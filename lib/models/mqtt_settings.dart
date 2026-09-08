import 'json_tolerant.dart';

/// Réglages de la liaison MQTT (addendum § 8, ligne « F1.9 »).
///
/// Le `deviceId` n'est pas un simple identifiant : sur un broker public, c'est
/// la SEULE chose qui sépare vos topics de ceux des autres. Il doit être long
/// et tiré au hasard.
class MqttSettings {
  const MqttSettings({
    this.host = defaultHost,
    this.port = defaultPort,
    this.deviceId = '',
    this.username,
    this.password,
  });

  /// Broker public par défaut : simulation UNIQUEMENT.
  ///
  /// Il est ouvert à tous, sans authentification. Acceptable seulement parce
  /// que rien de physique n'est branché sur le banc d'essai. Un vrai volet ne
  /// se pointe jamais sur un broker public, quelles que soient les
  /// précautions : un identifiant obscur n'est pas une authentification
  /// (addendum § 6).
  static const String defaultHost = 'broker.hivemq.com';

  /// 1883 : MQTT en clair. Un broker local exposé demanderait TLS sur 8883.
  static const int defaultPort = 1883;

  /// Longueur minimale acceptée pour un identifiant.
  ///
  /// En dessous, la collision avec un autre utilisateur du broker public
  /// devient plausible, et une collision signifie voir bouger la bâche de
  /// quelqu'un d'autre.
  static const int minimumDeviceIdLength = 8;

  final String host;
  final int port;
  final String deviceId;
  final String? username;
  final String? password;

  /// Base de tous les topics : `aquacontrol/<deviceId>`.
  String get topicBase => 'aquacontrol/$deviceId';

  String get topicTelemetry => '$topicBase/state/telemetry';
  String get topicOnline => '$topicBase/state/online';
  String get topicFilterAlert => '$topicBase/state/alert/filter';

  /// Filtre d'abonnement : tous les topics d'état.
  String get topicStateWildcard => '$topicBase/state/#';

  String commandTopic(String leaf) => '$topicBase/cmd/$leaf';

  bool get isUsable =>
      host.trim().isNotEmpty &&
      port > 0 &&
      deviceId.trim().length >= minimumDeviceIdLength;

  /// Le broker est-il public, donc réservé à la simulation ?
  ///
  /// Sert à afficher l'avertissement du § 6 : sur un broker public, la liaison
  /// ne doit jamais commander un vrai volet.
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
      // Bornes des ports TCP valides.
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

  /// Ne montre jamais le mot de passe, pas même dans un journal.
  @override
  String toString() => 'MqttSettings($host:$port, $deviceId)';
}
