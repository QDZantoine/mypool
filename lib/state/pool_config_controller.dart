import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_store.dart';
import '../models/chemical_product.dart';
import '../models/mqtt_settings.dart';
import '../models/pool_config.dart';

/// Configuration du bassin et réglages de liaison, en mémoire et sur disque.
///
/// N'effectue AUCUN calcul : il charge, il valide les bornes que les modèles
/// imposent déjà, il enregistre. Les doses, les plannings et l'équilibre de
/// l'eau se calculent dans `domain/`.
///
/// L'état initial est la configuration par défaut, et non un état « en
/// chargement » : l'application est utilisable dès la première image, avec une
/// piscine de 40 m3 au chlore stabilisé, et la valeur enregistrée la remplace
/// dès qu'elle est lue. C'est ce qui évite un écran d'attente au lancement.
class PoolConfigController extends StateNotifier<PoolConfig> {
  PoolConfigController({required this._store}) : super(const PoolConfig());

  final SettingsStore _store;

  bool _loaded = false;

  /// La configuration enregistrée a-t-elle été relue ?
  ///
  /// Sert à ne pas écraser le disque avec les valeurs par défaut si un écran
  /// enregistre avant la fin du chargement.
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

  /// Remplace la configuration et l'enregistre.
  Future<void> replace(PoolConfig config) async {
    state = config;
    await _store.savePoolConfig(config);
  }

  /// Modifie un champ et enregistre.
  ///
  /// Les écrans passent par ici plutôt que de reconstruire un [PoolConfig]
  /// complet : un champ oublié reprendrait sa valeur par défaut au lieu de
  /// garder la valeur en place.
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

  /// Recalcule le volume depuis les dimensions saisies.
  ///
  /// Proposé et non imposé : un bassin en haricot ou à fond incliné n'est pas
  /// un pavé droit, et l'utilisateur doit pouvoir saisir son volume réel.
  Future<void> useVolumeFromDimensions() async {
    await replace(state.copyWith(volumeM3: state.volumeFromDimensions));
  }

  /// Déclare un produit et sa concentration.
  ///
  /// C'est ce qui rend les doses justes : le moteur divise la masse de matière
  /// active par la concentration DÉCLARÉE ici. Un chlore à 56 % pris pour du
  /// 90 % donne un tiers de dose en moins.
  Future<void> declareProduct(ChemicalProduct product) async {
    await replace(
      state.copyWith(inventory: state.inventory.withProduct(product)),
    );
  }

  /// Enregistre l'acceptation de l'avertissement de sécurité du volet.
  ///
  /// Sans elle, aucune commande de volet n'agit (règle de sécurité n° 4). Le
  /// consentement est persisté : le redemander à chaque ouverture de
  /// l'application le transformerait en clic réflexe, ce qui lui ferait perdre
  /// tout son sens.
  Future<void> setSafetyConsent({required bool given}) async {
    await replace(state.copyWith(safetyConsentGiven: given));
  }
}

/// Réglages de la liaison MQTT (addendum § 8, ligne « F1.9 »).
///
/// Séparés de [PoolConfigController] parce qu'ils changent pour d'autres
/// raisons : on remplace un broker sans toucher au volume du bassin.
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
