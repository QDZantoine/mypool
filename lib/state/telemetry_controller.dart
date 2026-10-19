import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/devices/pool_device_driver.dart';
import '../data/devices/telemetry.dart';
import '../data/devices/wokwi_mqtt_driver.dart';
import '../domain/reading_sampler.dart';
import '../models/water_reading.dart';

class TelemetryState {
  const TelemetryState({
    this.telemetry,
    this.isModuleOnline = false,
    this.isFresh = false,
    this.filterAlert = false,
    this.errorMessage,
  });

  final PoolTelemetry? telemetry;

  final bool isModuleOnline;

  final bool isFresh;

  final bool filterAlert;

  final String? errorMessage;

  bool get hasLiveValues => isFresh && telemetry != null;

  double? get livePh => hasLiveValues ? telemetry!.ph : null;

  double? get liveTemperatureC =>
      hasLiveValues ? telemetry!.temperatureC : null;

  TelemetryState copyWith({
    PoolTelemetry? telemetry,
    bool? isModuleOnline,
    bool? isFresh,
    bool? filterAlert,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TelemetryState(
      telemetry: telemetry ?? this.telemetry,
      isModuleOnline: isModuleOnline ?? this.isModuleOnline,
      isFresh: isFresh ?? this.isFresh,
      filterAlert: filterAlert ?? this.filterAlert,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  String toString() =>
      'TelemetryState(en ligne: $isModuleOnline, '
      'frais: $isFresh, pH ${telemetry?.ph})';
}

class TelemetryController extends StateNotifier<TelemetryState> {
  TelemetryController({
    required this._driver,
    required this._onSample,
    required this._lastSensorReading,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const TelemetryState());

  final WokwiMqttDriver? _driver;

  final Future<WaterReading?> Function(WaterReading) _onSample;

  final Future<WaterReading?> Function() _lastSensorReading;

  final DateTime Function() _clock;

  StreamSubscription<PoolTelemetry>? _telemetrySubscription;
  StreamSubscription<bool>? _onlineSubscription;

  WaterReading? _lastRecorded;
  bool _referenceLoaded = false;

  int framesReceived = 0;

  int samplesRecorded = 0;

  Future<void> start() async {
    final WokwiMqttDriver? driver = _driver;
    if (driver == null) {
      return;
    }
    _telemetrySubscription ??= driver.telemetryStream.listen(_handleFrame);
    _onlineSubscription ??= driver.moduleOnlineStream.listen(_handleOnline);
    try {
      await driver.start();
      state = state.copyWith(clearError: true);
    } on DeviceException catch (error) {

      state = state.copyWith(
        isModuleOnline: false,
        isFresh: false,
        errorMessage: error.message,
      );
    }
  }

  void _handleOnline(bool online) {
    state = state.copyWith(
      isModuleOnline: online,

      isFresh: online ? state.isFresh : false,
    );
  }

  void _handleFrame(PoolTelemetry telemetry) {
    framesReceived++;
    state = state.copyWith(
      telemetry: telemetry,
      isModuleOnline: true,
      isFresh: true,
      filterAlert: telemetry.filterAlert,
      clearError: true,
    );
    unawaited(_maybeRecord(telemetry));
  }

  Future<void> _maybeRecord(PoolTelemetry telemetry) async {
    if (!_referenceLoaded) {

      _lastRecorded = await _lastSensorReading();
      _referenceLoaded = true;
    }

    final WaterReading? candidate = ReadingSampler.sample(
      at: _clock(),
      lastRecorded: _lastRecorded,
      ph: telemetry.ph,
      temperatureC: telemetry.temperatureC,
    );
    if (candidate == null) {
      return;
    }

    final WaterReading? recorded = await _onSample(candidate);
    if (recorded != null) {

      _lastRecorded = recorded;
      samplesRecorded++;
    }
  }

  Future<Duration> testConnection() async {
    final WokwiMqttDriver? driver = _driver;
    if (driver == null) {
      throw const DeviceException(
        'Aucune liaison MQTT n’est configurée. Choisissez ce type de liaison '
        'dans les réglages pour la tester.',
        technicalDetail: 'telemetryController sans pilote MQTT',
      );
    }
    try {
      final Duration latency = await driver.ping();
      state = state.copyWith(clearError: true);
      return latency;
    } on DeviceException catch (error) {
      state = state.copyWith(errorMessage: error.message);
      rethrow;
    }
  }

  void refreshFreshness() {
    state = state.copyWith(isFresh: _driver?.hasFreshTelemetry ?? false);
  }

  @override
  void dispose() {
    unawaited(_telemetrySubscription?.cancel());
    unawaited(_onlineSubscription?.cancel());
    _telemetrySubscription = null;
    _onlineSubscription = null;
    super.dispose();
  }
}
