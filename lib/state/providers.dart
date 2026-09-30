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

/// Câblage de l'application.
///
/// Ce fichier ne contient aucune logique : il dit seulement qui dépend de qui.
/// Chaque provider d'infrastructure est surchargeable, et les tests
/// remplacent le magasin de réglages et l'historique par leurs doubles en
/// mémoire — ce qui rend tous les contrôleurs testables sans disque ni réseau.

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------

/// Magasin des réglages. Surchargé en test par [InMemorySettingsStore].
final Provider<SettingsStore> settingsStoreProvider = Provider<SettingsStore>(
  (Ref ref) => PreferencesSettingsStore(),
);

/// Historique des mesures. Surchargé en test par
/// [InMemoryReadingsRepository].
final Provider<ReadingsRepository> readingsRepositoryProvider =
    Provider<ReadingsRepository>((Ref ref) {
      final ReadingsDatabase database = ReadingsDatabase();
      ref.onDispose(() => unawaited(database.close()));
      return database;
    });

/// Service Météo.
final Provider<WeatherService> weatherServiceProvider =
    Provider<WeatherService>((Ref ref) {
      final WeatherService service = WeatherService();
      ref.onDispose(service.dispose);
      return service;
    });

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Matériel
// ---------------------------------------------------------------------------

/// Les seuls réglages qui justifient de reconstruire le pilote.
///
/// Sans ce filtrage, renommer le bassin fermerait et rouvrirait la liaison
/// MQTT — et couperait un mouvement de volet en cours.
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

/// Pilote matériel, choisi d'après la configuration.
///
/// C'est le seul endroit du projet qui connaît la liste des implémentations :
/// un nouveau matériel s'ajoute ici et nulle part ailleurs.
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
          // Pas encore écrits. Un pilote qui échoue avec une phrase claire
          // vaut mieux qu'un repli silencieux sur la simulation : croire
          // qu'on pilote sa piscine alors qu'on ne pilote rien est pire.
          driver = UnavailableDriver(inputs.kind);
      }

      // Le pilote MQTT est libéré par son propre provider ; les autres le sont
      // ici, quand la configuration change de type de liaison.
      if (inputs.kind != DriverKind.mqtt) {
        ref.onDispose(() => unawaited(driver.dispose()));
      }
      return driver;
    });

/// Transport MQTT, ou `null` quand la liaison choisie n'est pas MQTT.
///
/// Isolé du pilote pour une raison de test : c'est le seul élément qui touche
/// réellement au réseau. Le remplacer suffit à exercer le pilote, le
/// contrôleur de télémétrie et l'échantillonnage tels qu'ils tourneront en
/// production.
final Provider<MqttTransport?> mqttTransportProvider = Provider<MqttTransport?>(
  (Ref ref) {
    final _DriverInputs inputs = ref.watch(_driverInputsProvider);
    if (inputs.kind != DriverKind.mqtt) {
      return null;
    }
    return MqttClientTransport(settings: inputs.mqtt);
  },
);

/// Pilote MQTT, ou `null` quand la liaison choisie n'est pas MQTT.
///
/// Exposé séparément parce que la télémétrie n'existe que sur ce transport :
/// c'est le seul pilote qui remonte des mesures.
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

/// Pilotage du volet.
///
/// La configuration est passée en FONCTION et non en valeur : le contrôleur la
/// relit à chaque commande, de sorte qu'un consentement retiré dans les
/// réglages bloque immédiatement la commande suivante (règle de sécurité
/// n° 4).
final StateNotifierProvider<CoverController, CoverStatus>
coverControllerProvider = StateNotifierProvider<CoverController, CoverStatus>(
  (Ref ref) => CoverController(
    driver: ref.watch(deviceDriverProvider),
    config: () => ref.read(poolConfigProvider),
  ),
);

// ---------------------------------------------------------------------------
// Mesures
// ---------------------------------------------------------------------------

final StateNotifierProvider<WaterReadingsController, ReadingsState>
readingsProvider =
    StateNotifierProvider<WaterReadingsController, ReadingsState>(
      (Ref ref) => WaterReadingsController(
        repository: ref.watch(readingsRepositoryProvider),
      ),
    );

/// Télémétrie du module et échantillonnage automatique.
final StateNotifierProvider<TelemetryController, TelemetryState>
telemetryProvider = StateNotifierProvider<TelemetryController, TelemetryState>((
  Ref ref,
) {
  final ReadingsRepository repository = ref.watch(readingsRepositoryProvider);
  return TelemetryController(
    driver: ref.watch(mqttDriverProvider),
    // L'écriture passe par le contrôleur d'historique, pour que la liste
    // affichée se mette à jour en même temps que la base.
    onSample: (WaterReading reading) async {
      final StoredReading? stored = await ref
          .read(readingsProvider.notifier)
          .record(reading);
      return stored?.reading;
    },
    // La référence de la règle est relue en base, et non prise dans la
    // liste en mémoire : le rythme d'une heure doit survivre à un
    // redémarrage de l'application.
    lastSensorReading: () async =>
        (await repository.latest(source: MeasurementSource.sensor))?.reading,
  );
});

// ---------------------------------------------------------------------------
// Amorçage
// ---------------------------------------------------------------------------

/// Charge tout ce qui doit l'être avant d'ouvrir la première page.
///
/// L'ORDRE COMPTE, et c'est la raison d'être de cette fonction :
///
/// 1. les réglages de liaison en premier, parce que le pilote matériel se
///    construit à partir d'eux — le lire avant les aurait figés sur des
///    valeurs vides, et le module n'aurait jamais répondu ;
/// 2. la configuration du bassin, dont dépendent le choix du pilote et toutes
///    les doses ;
/// 3. l'historique, qui alimente les recommandations ;
/// 4. la télémétrie en dernier, parce qu'elle écrit dans l'historique.
///
/// Aucune étape ne bloque les suivantes : chaque contrôleur rattrape ses
/// propres pannes et laisse un message affichable. L'application s'ouvre même
/// si tout échoue.
Future<void> bootstrap(ProviderContainer container) async {
  await container.read(mqttSettingsProvider.notifier).load();
  await container.read(poolConfigProvider.notifier).load();
  await container.read(readingsProvider.notifier).load();
  await container.read(telemetryProvider.notifier).start();
  container.read(connectionNotifierProvider.notifier).startMonitoring();
}
