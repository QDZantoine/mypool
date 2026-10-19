import 'dart:async';
import 'dart:convert';

import '../../models/filtration_schedule.dart';
import '../../models/mqtt_settings.dart';
import 'mqtt_transport.dart';
import 'pool_device_driver.dart';
import 'telemetry.dart';

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

  static const String cmdCover = 'cover';
  static const String cmdCoverCalibrate = 'cover-calibrate';
  static const String cmdPump = 'pump';
  static const String cmdHeater = 'heater';
  static const String cmdSetpoint = 'setpoint';
  static const String cmdFilterReset = 'filter-reset';
  static const String cmdPing = 'ping';

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

  final Duration telemetryTimeout;

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

  PoolTelemetry? get lastTelemetry => _lastTelemetry;

  Stream<PoolTelemetry> get telemetryStream => _telemetry.stream;

  Stream<bool> get moduleOnlineStream => _online.stream;

  bool get isModuleOnline => _moduleOnline;

  bool get filterAlert => _filterAlert;

  bool get hasFreshTelemetry {
    final PoolTelemetry? last = _lastTelemetry;
    if (last == null) {
      return false;
    }
    return _clock().difference(last.receivedAt) <= telemetryFreshness;
  }

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
    if (_transport.isConnected) {
      return;
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
    if (!_transport.isConnected) {
      return;
    }
    try {
      await _transport.subscribe(_settings.topicStateWildcard);
    } on Exception {

    }
  }

  void _handleConnectionChange(bool connected) {
    if (connected) {
      _reconnectAttempt = 0;

      unawaited(_subscribeState());
      return;
    }

    _setModuleOnline(false);
    if (_started && !_disposed) {
      unawaited(_reconnect());
    }
  }

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
      } catch (_) {

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

      _setModuleOnline(message.payload.trim() == '1');
      return;
    }
    if (message.topic == _settings.topicFilterAlert) {
      _filterAlert = message.payload.trim() == '1';
    }
  }

  void _handleTelemetry(String payload) {
    if (payload.trim().isEmpty) {

      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {

      return;
    }

    if (decoded is! Map || decoded.isEmpty) {
      return;
    }

    final PoolTelemetry telemetry = PoolTelemetry.fromJson(
      decoded,
      receivedAt: _clock(),
    );
    _lastTelemetry = telemetry;
    _filterAlert = telemetry.filterAlert;

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
      throw const DeviceException(
        'Un problème est survenu, vérifier votre connexion internet.',
        technicalDetail: 'transport déconnecté',
      );
    }
  }

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

  @override
  Future<void> pulse(DeviceChannel channel, {required Duration autoOff}) async {

    CoverSafety.checkCoverAutoOff(channel, autoOff);

    switch (channel) {
      case DeviceChannel.coverOpen:
      case DeviceChannel.coverClose:

        await _publishCommand(
          cmdCover,
          channel == DeviceChannel.coverOpen ? 'open' : 'close',
        );
      case DeviceChannel.pump:
      case DeviceChannel.heater:

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
        _optimisticUpdate(pumpOn: on);
      case DeviceChannel.heater:
        await _publishCommand(cmdHeater, on ? 'on' : 'off');
        _optimisticUpdate(heaterOn: on);
      case DeviceChannel.coverOpen:
      case DeviceChannel.coverClose:

        throw DeviceException(
          'Un volet ne se commande jamais en marche continue.',
          technicalDetail: 'setRelay refusé sur ${channel.name}',
        );
    }
  }

  void _optimisticUpdate({bool? pumpOn, bool? heaterOn}) {
    final PoolTelemetry current =
        _lastTelemetry ?? PoolTelemetry(receivedAt: _clock());
    final PoolTelemetry updated = current.copyWith(
      pumpOn: pumpOn ?? current.pumpOn,
      heaterOn: heaterOn ?? current.heaterOn,
      receivedAt: _clock(),
    );
    _lastTelemetry = updated;
    if (!_telemetry.isClosed) {
      _telemetry.add(updated);
    }
  }

  @override
  Future<bool> relayState(DeviceChannel channel) async {

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

    _requireFreshTelemetry();
    return null;
  }

  @override
  Future<bool?> inputState(DeviceInput input) async {

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

    await _publishCommand(cmdPing, '1');

    try {
      final PoolTelemetry answer = await _telemetry.stream
          .firstWhere(
            (PoolTelemetry t) => !t.receivedAt.isBefore(
              sentAt.subtract(const Duration(milliseconds: 100)),
            ),
          )
          .timeout(telemetryTimeout);
      final Duration latency = answer.receivedAt.difference(sentAt);
      return latency.isNegative ? Duration.zero : latency;
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

    throw const DeviceException(
      'Ce module ne sait pas mémoriser un planning de filtration : en liaison '
      'MQTT, la filtration est commandée par l’application, et s’arrête donc '
      'si le téléphone est éteint.',
      technicalDetail: 'pushFiltrationSchedule non supporté (addendum § 8.1)',
    );
  }

  @override
  Future<void> clearFiltrationSchedule() async {

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
