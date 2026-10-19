import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connection_notifier.dart';
import '../data/devices/mqtt_transport.dart';
import '../data/devices/pool_device_driver.dart';
import '../data/devices/simulation_driver.dart';
import '../data/devices/unavailable_driver.dart';
import '../data/devices/wokwi_mqtt_driver.dart';
import '../data/readings_database.dart';
import '../data/settings_store.dart';
import '../services/weather-service.dart';
import '../models/mqtt_settings.dart';
import '../models/pool_config.dart';
import '../models/water_reading.dart';
import 'cover_controller.dart';
import 'pool_config_controller.dart';
import 'telemetry_controller.dart';
import 'water_readings_controller.dart';

final Provider<SettingsStore> settingsStoreProvider = Provider<SettingsStore>(
  (Ref ref) => PreferencesSettingsStore(),
);

final Provider<ReadingsRepository> readingsRepositoryProvider =
    Provider<ReadingsRepository>((Ref ref) {
      final ReadingsDatabase database = ReadingsDatabase();
      ref.onDispose(() => unawaited(database.close()));
      return database;
    });

final Provider<WeatherService> weatherServiceProvider =
    Provider<WeatherService>((Ref ref) {
      final WeatherService service = WeatherService();
      ref.onDispose(service.dispose);
      return service;
    });

final StateNotifierProvider<PoolConfigController, PoolConfig>
poolConfigProvider = StateNotifierProvider<PoolConfigController, PoolConfig>(
  (Ref ref) => PoolConfigController(store: ref.watch(settingsStoreProvider)),
);

final StateNotifierProvider<MqttSettingsController, MqttSettings>
mqttSettingsProvider =
    StateNotifierProvider<MqttSettingsController, MqttSettings>(
      (Ref ref) =>
          MqttSettingsController(store: ref.watch(settingsStoreProvider)),
    );

typedef _DriverInputs = ({
  DriverKind kind,
  double coverTravelSeconds,
  MqttSettings mqtt,
});

final Provider<_DriverInputs> _driverInputsProvider = Provider<_DriverInputs>(
  (Ref ref) => (
    kind: ref.watch(poolConfigProvider.select((PoolConfig c) => c.driver)),
    coverTravelSeconds: ref.watch(
      poolConfigProvider.select((PoolConfig c) => c.coverTravelSeconds),
    ),
    mqtt: ref.watch(mqttSettingsProvider),
  ),
);

final Provider<PoolDeviceDriver> deviceDriverProvider =
    Provider<PoolDeviceDriver>((Ref ref) {
      final _DriverInputs inputs = ref.watch(_driverInputsProvider);

      final PoolDeviceDriver driver;
      switch (inputs.kind) {
        case DriverKind.simulation:
          driver = SimulationDriver(
            coverTravel: Duration(
              milliseconds: (inputs.coverTravelSeconds * 1000).round(),
            ),
          );
        case DriverKind.mqtt:
          driver = ref.watch(mqttDriverProvider)!;
        case DriverKind.localModule:
        case DriverKind.homeAssistant:

          driver = UnavailableDriver(inputs.kind);
      }

      if (inputs.kind != DriverKind.mqtt) {
        ref.onDispose(() => unawaited(driver.dispose()));
      }
      return driver;
    });

final Provider<MqttTransport?> mqttTransportProvider = Provider<MqttTransport?>(
  (Ref ref) {
    final _DriverInputs inputs = ref.watch(_driverInputsProvider);
    if (inputs.kind != DriverKind.mqtt) {
      return null;
    }
    return MqttClientTransport(settings: inputs.mqtt);
  },
);

final Provider<WokwiMqttDriver?> mqttDriverProvider =
    Provider<WokwiMqttDriver?>((Ref ref) {
      final MqttTransport? transport = ref.watch(mqttTransportProvider);
      if (transport == null) {
        return null;
      }
      final WokwiMqttDriver driver = WokwiMqttDriver(
        settings: ref.watch(mqttSettingsProvider),
        transport: transport,
      );
      ref.onDispose(() => unawaited(driver.dispose()));
      return driver;
    });

final StateNotifierProvider<CoverController, CoverStatus>
coverControllerProvider = StateNotifierProvider<CoverController, CoverStatus>(
  (Ref ref) => CoverController(
    driver: ref.watch(deviceDriverProvider),
    config: () => ref.read(poolConfigProvider),
  ),
);

final StateNotifierProvider<WaterReadingsController, ReadingsState>
readingsProvider =
    StateNotifierProvider<WaterReadingsController, ReadingsState>(
      (Ref ref) => WaterReadingsController(
        repository: ref.watch(readingsRepositoryProvider),
      ),
    );

final StateNotifierProvider<TelemetryController, TelemetryState>
telemetryProvider = StateNotifierProvider<TelemetryController, TelemetryState>((
  Ref ref,
) {
  final ReadingsRepository repository = ref.watch(readingsRepositoryProvider);
  return TelemetryController(
    driver: ref.watch(mqttDriverProvider),

    onSample: (WaterReading reading) async {
      final StoredReading? stored = await ref
          .read(readingsProvider.notifier)
          .record(reading);
      return stored?.reading;
    },

    lastSensorReading: () async =>
        (await repository.latest(source: MeasurementSource.sensor))?.reading,
  );
});

Future<void> bootstrap(ProviderContainer container) async {
  await container.read(mqttSettingsProvider.notifier).load();
  await container.read(poolConfigProvider.notifier).load();
  await container.read(readingsProvider.notifier).load();
  await container.read(telemetryProvider.notifier).start();
  container.read(connectionNotifierProvider.notifier).startMonitoring();
}
