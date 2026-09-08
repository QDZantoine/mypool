import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/devices/mqtt_transport.dart';
import 'package:mypool/data/devices/pool_device_driver.dart';
import 'package:mypool/data/devices/wokwi_mqtt_driver.dart';
import 'package:mypool/data/readings_database.dart';
import 'package:mypool/data/settings_store.dart';
import 'package:mypool/models/filtration_schedule.dart';
import 'package:mypool/models/mqtt_settings.dart';
import 'package:mypool/models/pool_config.dart';
import 'package:mypool/models/water_reading.dart';
import 'package:mypool/state/derived_providers.dart';
import 'package:mypool/state/providers.dart';
import 'package:mypool/state/telemetry_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/devices/fake_mqtt_transport.dart';

final DateTime _start = DateTime.utc(2026, 7, 15, 10);

String _telemetry({double ph = 7.24, double tempC = 26.4}) {
  return jsonEncode(<String, dynamic>{
    'deviceId': 'a7f3c1e9b2xx',
    'ph': ph,
    'tempC': tempC,
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('câblage par défaut', () {
    test(
      'sans surcharge, les implémentations réelles sont utilisées',
      () async {
        // Vérifie que le câblage de production s'assemble : préférences de la
        // plateforme et base SQLite, sans double en mémoire.
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final ProviderContainer container = ProviderContainer();
        addTearDown(container.dispose);

        expect(
          container.read(settingsStoreProvider),
          isA<PreferencesSettingsStore>(),
        );
        expect(
          container.read(readingsRepositoryProvider),
          isA<ReadingsDatabase>(),
        );

        // Et le tout fonctionne bout en bout.
        await container.read(poolConfigProvider.notifier).edit(volumeM3: 55.0);
        expect(container.read(poolConfigProvider).volumeM3, 55.0);

        final ProviderContainer reopened = ProviderContainer();
        addTearDown(reopened.dispose);
        await reopened.read(poolConfigProvider.notifier).load();
        expect(reopened.read(poolConfigProvider).volumeM3, 55.0);
      },
    );
  });

  group('liaison MQTT complète', () {
    late FakeMqttTransport transport;
    late ProviderContainer container;

    ProviderContainer buildMqtt() {
      transport = FakeMqttTransport();
      final InMemoryReadingsRepository readings = InMemoryReadingsRepository();
      final ProviderContainer result = ProviderContainer(
        overrides: <Override>[
          settingsStoreProvider.overrideWithValue(
            InMemorySettingsStore(
              poolConfig: const PoolConfig().copyWith(driver: DriverKind.mqtt),
              mqttSettings: const MqttSettings(deviceId: 'a7f3c1e9b2xx'),
            ),
          ),
          readingsRepositoryProvider.overrideWithValue(readings),
          // Seul le transport est remplacé : le pilote, le contrôleur et
          // l'échantillonnage sont ceux de production, y compris la condition
          // qui n'instancie le pilote que si la liaison est MQTT.
          mqttTransportProvider.overrideWith(
            (Ref ref) =>
                ref.watch(
                      poolConfigProvider.select((PoolConfig c) => c.driver),
                    ) ==
                    DriverKind.mqtt
                ? transport
                : null,
          ),
        ],
      );
      addTearDown(result.dispose);
      return result;
    }

    setUp(() {
      container = buildMqtt();
    });

    Future<void> deliver(String payload) async {
      transport.deliver('aquacontrol/a7f3c1e9b2xx/state/telemetry', payload);
      await pumpEventQueue();
    }

    test('le pilote MQTT devient le pilote matériel', () async {
      await bootstrap(container);
      expect(container.read(deviceDriverProvider), isA<WokwiMqttDriver>());
      expect(container.read(mqttDriverProvider), isNotNull);
    });

    test('une trame alimente l’état courant et l’historique', () async {
      await bootstrap(container);

      await deliver(_telemetry(ph: 7.24, tempC: 26.4));

      // État en direct.
      final TelemetryState telemetry = container.read(telemetryProvider);
      expect(telemetry.livePh, 7.24);
      expect(telemetry.liveTemperatureC, 26.4);

      // Première mesure : la règle la retient et elle passe par le contrôleur
      // d'historique, donc la liste affichée se met à jour.
      expect(container.read(readingsProvider).recent.length, 1);
      expect(container.read(readingsProvider).latestSensor?.ph, 7.24);
    });

    test('la sonde fait foi sur le pH, la saisie apporte le reste', () async {
      await bootstrap(container);

      // Une saisie sans température.
      await container
          .read(readingsProvider.notifier)
          .record(WaterReading(takenAt: _start, ph: 7.9, tac: 100.0));
      await deliver(_telemetry(ph: 7.24, tempC: 26.4));

      final WaterReading? effective = container.read(effectiveReadingProvider);
      // La SONDE fait foi sur le pH : sa lecture a deux secondes, la saisie
      // décrit l'eau d'un autre moment. Doser sur la valeur périmée ferait
      // verser à côté.
      expect(effective?.ph, 7.24);
      expect(effective?.temperature, 26.4);
      // Le TAC saisi est conservé : aucune sonde ne le mesure, et c'est lui
      // qui fixe la dose de pH.
      expect(effective?.tac, 100.0);
      // Et le planning de filtration en découle : 26,4 / 2 = 13,2 h = 792 min.
      expect(container.read(filtrationPlanProvider)?.recommendedMinutes, 792);
    });

    test('une sonde partielle laisse la saisie combler le trou', () async {
      // Cas réel : la sonde pH est débranchée mais le NTC répond. La trame
      // arrive donc avec une température et sans pH.
      await bootstrap(container);
      await container
          .read(readingsProvider.notifier)
          .record(WaterReading(takenAt: _start, ph: 7.6, tac: 100.0));
      await deliver(
        jsonEncode(<String, dynamic>{
          'deviceId': 'a7f3c1e9b2xx',
          'tempC': 24.0,
        }),
      );

      final WaterReading? effective = container.read(effectiveReadingProvider);
      // La sonde impose la température qu'elle mesure.
      expect(effective?.temperature, 24.0);
      // Et le pH saisi reste, faute de mieux : mieux vaut une valeur datée
      // dont on connaît l'âge qu'aucune valeur.
      expect(effective?.ph, 7.6);
      expect(effective?.tac, 100.0);
    });

    test('sans saisie, la télémétrie devient la mesure de référence', () async {
      await bootstrap(container);
      await deliver(_telemetry(ph: 7.8, tempC: 26.0));

      final WaterReading? effective = container.read(effectiveReadingProvider);
      expect(effective?.ph, 7.8);
      expect(effective?.source, MeasurementSource.sensor);
      // Et les recommandations suivent.
      // 7,8 - 7,2 = 0,60 ; 0,60 x 40 x 60 = 1 440 g
      expect(
        container.read(recommendationsProvider).first.quantity,
        closeTo(1440.0, 0.001),
      );
    });

    test('le pilote MQTT refuse d’écrire un planning', () async {
      await bootstrap(container);
      final PoolDeviceDriver driver = container.read(deviceDriverProvider);

      // Limite assumée du banc d'essai (addendum § 8.1).
      await expectLater(
        driver.pushFiltrationSchedule(
          container.read(filtrationPlanProvider) ?? FiltrationSchedule.empty,
        ),
        throwsA(isA<DeviceException>()),
      );
    });

    test('changer de liaison libère le pilote MQTT', () async {
      await bootstrap(container);
      final WokwiMqttDriver? mqtt = container.read(mqttDriverProvider);
      expect(mqtt, isNotNull);

      await container
          .read(poolConfigProvider.notifier)
          .edit(driver: DriverKind.simulation);

      expect(container.read(mqttDriverProvider), isNull);
      // Le pilote libéré refuse toute nouvelle commande.
      await expectLater(
        mqtt!.setRelay(DeviceChannel.pump, on: true),
        throwsA(isA<DeviceException>()),
      );
    });
  });

  group('transport réel', () {
    test('il s’instancie sans toucher au réseau', () {
      // Le constructeur ne connecte pas : la connexion est explicite. Cela
      // permet de construire le pilote au démarrage sans attendre le broker.
      final MqttClientTransport transport = MqttClientTransport(
        settings: const MqttSettings(deviceId: 'a7f3c1e9b2xx'),
      );
      expect(transport.isConnected, isFalse);
    });
  });
}
