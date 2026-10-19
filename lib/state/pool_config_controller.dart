import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_store.dart';
import '../models/chemical_product.dart';
import '../models/mqtt_settings.dart';
import '../models/pool_config.dart';

class PoolConfigController extends StateNotifier<PoolConfig> {
  PoolConfigController({required this._store}) : super(const PoolConfig());

  final SettingsStore _store;

  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load() async {
    final PoolConfig stored = await _store.loadPoolConfig();
    if (dotenv.isInitialized && dotenv.env.containsKey('MQTT_HOST')) {
      state = stored.copyWith(driver: DriverKind.mqtt);
      _loaded = true;
      return;
    }
    state = stored;
    _loaded = true;
  }

  Future<void> replace(PoolConfig config) async {
    state = config;
    await _store.savePoolConfig(config);
  }

  Future<void> edit({
    String? name,
    double? volumeM3,
    double? lengthM,
    double? widthM,
    double? averageDepthM,
    TreatmentType? treatment,
    FilterType? filter,
    CoverType? cover,
    double? pumpFlowM3PerHour,
    double? pumpEfficiency,
    double? coverTravelSeconds,
    DriverKind? driver,
  }) async {
    await replace(
      state.copyWith(
        name: name,
        volumeM3: volumeM3,
        lengthM: lengthM,
        widthM: widthM,
        averageDepthM: averageDepthM,
        treatment: treatment,
        filter: filter,
        cover: cover,
        pumpFlowM3PerHour: pumpFlowM3PerHour,
        pumpEfficiency: pumpEfficiency,
        coverTravelSeconds: coverTravelSeconds,
        driver: driver,
      ),
    );
  }

  Future<void> useVolumeFromDimensions() async {
    await replace(state.copyWith(volumeM3: state.volumeFromDimensions));
  }

  Future<void> declareProduct(ChemicalProduct product) async {
    await replace(
      state.copyWith(inventory: state.inventory.withProduct(product)),
    );
  }

  Future<void> setSafetyConsent({required bool given}) async {
    await replace(state.copyWith(safetyConsentGiven: given));
  }
}

class MqttSettingsController extends StateNotifier<MqttSettings> {
  MqttSettingsController({required this._store}) : super(const MqttSettings());

  final SettingsStore _store;

  Future<void> load() async {
    final MqttSettings stored = await _store.loadMqttSettings();
    if (dotenv.isInitialized && dotenv.env.containsKey('MQTT_HOST')) {
      final String envDeviceId = dotenv.env['MQTT_DEVICE_ID'] ?? 'a7f3c1e9b2';
      final String envHost = dotenv.env['MQTT_HOST'] ?? MqttSettings.defaultHost;
      final int envPort = int.tryParse(dotenv.env['MQTT_PORT'] ?? '') ?? MqttSettings.defaultPort;

      if (stored.deviceId.isEmpty ||
          stored.deviceId == 'wokwi-esp32-pool' ||
          stored.host.contains('hivemq.cloud') ||
          stored.deviceId != envDeviceId) {
        final MqttSettings updated = stored.copyWith(
          host: envHost,
          port: envPort,
          deviceId: envDeviceId,
          username: dotenv.env['MQTT_USER'],
          password: dotenv.env['MQTT_PASSWORD'],
        );
        state = updated;
        await replace(updated);
        return;
      }
    }
    state = stored;
  }

  Future<void> replace(MqttSettings settings) async {
    state = settings;
    await _store.saveMqttSettings(settings);
  }

  Future<void> edit({
    String? host,
    int? port,
    String? deviceId,
    String? username,
    String? password,
  }) async {
    await replace(
      state.copyWith(
        host: host,
        port: port,
        deviceId: deviceId,
        username: username,
        password: password,
      ),
    );
  }
}
