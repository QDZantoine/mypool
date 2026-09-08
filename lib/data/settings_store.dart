import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/mqtt_settings.dart';
import '../models/pool_config.dart';

/// Ce dont l'application a besoin pour retrouver ses réglages au lancement.
///
/// L'interface existe pour deux raisons : elle permet de tester les couches
/// au-dessus sans stockage réel, et elle laisse la porte ouverte à un
/// stockage chiffré pour les identifiants du broker (voir la note de
/// [PreferencesSettingsStore] sur le mot de passe MQTT).
abstract class SettingsStore {
  Future<PoolConfig> loadPoolConfig();

  Future<void> savePoolConfig(PoolConfig config);

  Future<MqttSettings> loadMqttSettings();

  Future<void> saveMqttSettings(MqttSettings settings);

  /// Efface tout. Utilisé par « repartir de zéro » dans les réglages.
  Future<void> clear();
}

/// Réglages stockés dans les préférences de la plateforme.
///
/// Règle du projet appliquée sans exception ici : **l'application doit
/// toujours s'ouvrir**. Une valeur corrompue, une clé absente, un JSON
/// illisible, une plateforme qui refuse l'accès au stockage — tout retombe sur
/// les valeurs par défaut au lieu de lever. Un écran d'erreur au lancement
/// serait le pire résultat possible, puisqu'il empêcherait justement de
/// corriger le réglage fautif.
///
/// LIMITE ASSUMÉE : le mot de passe du broker MQTT est stocké **en clair**.
/// `shared_preferences` n'est pas un coffre-fort : sur Android c'est un
/// fichier XML lisible par root ou par une sauvegarde, sur iOS un plist. Pour
/// un broker local sur le réseau domestique, le risque est faible et accepté.
/// Il ne l'est plus dès que le broker est exposé sur Internet : il faudra
/// alors un stockage chiffré, et c'est la raison de l'interface
/// [SettingsStore].
class PreferencesSettingsStore implements SettingsStore {
  PreferencesSettingsStore({this._preferences});

  /// Clés versionnées : un changement incompatible de format prendra un
  /// suffixe `.v2`, ce qui laisse les anciennes valeurs en place au lieu de
  /// les réinterpréter de travers.
  static const String poolConfigKey = 'aquacontrol.poolConfig.v1';
  static const String mqttSettingsKey = 'aquacontrol.mqttSettings.v1';

  SharedPreferences? _preferences;

  Future<SharedPreferences?> _instance() async {
    if (_preferences != null) {
      return _preferences;
    }
    try {
      _preferences = await SharedPreferences.getInstance();
      return _preferences;
      // On attrape ici plus large qu'une Exception, contrairement à l'usage.
      // C'est délibéré et limité à ce chemin : l'ouverture du stockage est le
      // tout premier acte du lancement, et la règle du projet est absolue —
      // l'application doit toujours s'ouvrir. Un plugin de plateforme qui
      // lève une Error ne doit pas donner un écran noir au démarrage, faute
      // de quoi l'utilisateur n'a plus aucun moyen de corriger le réglage
      // fautif.
    } on Object {
      // Stockage indisponible : on continue sur les valeurs par défaut. Les
      // enregistrements suivants échoueront silencieusement, ce qui est
      // préférable à une application qui ne démarre pas.
      return null;
    }
  }

  /// Lit un objet JSON, ou `null` si rien d'exploitable n'est stocké.
  Future<Object?> _readJson(String key) async {
    final SharedPreferences? preferences = await _instance();
    if (preferences == null) {
      return null;
    }
    String? raw;
    try {
      raw = preferences.getString(key);
      // Même dérogation que dans _instance, et pour la même raison : une
      // valeur stockée sous un autre type — un entier écrit par une version
      // antérieure — fait lever un TypeError, qui est une Error et non une
      // Exception. La laisser passer rendrait l'application inouvrable sur
      // une préférence corrompue, exactement ce que la règle interdit.
    } on Object {
      return null;
    }
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      return jsonDecode(raw);
    } on FormatException {
      // JSON tronqué ou corrompu : les `fromJson` des modèles rendront les
      // valeurs par défaut.
      return null;
    }
  }

  Future<bool> _writeJson(String key, Map<String, dynamic> value) async {
    final SharedPreferences? preferences = await _instance();
    if (preferences == null) {
      return false;
    }
    try {
      return await preferences.setString(key, jsonEncode(value));
    } on Exception {
      return false;
    }
  }

  @override
  Future<PoolConfig> loadPoolConfig() async {
    // `PoolConfig.fromJson` est tolérant : `null` rend la piscine par défaut,
    // 40 m3 au chlore stabilisé, immédiatement utilisable.
    return PoolConfig.fromJson(await _readJson(poolConfigKey));
  }

  @override
  Future<void> savePoolConfig(PoolConfig config) async {
    await _writeJson(poolConfigKey, config.toJson());
  }

  @override
  Future<MqttSettings> loadMqttSettings() async {
    return MqttSettings.fromJson(await _readJson(mqttSettingsKey));
  }

  @override
  Future<void> saveMqttSettings(MqttSettings settings) async {
    await _writeJson(mqttSettingsKey, settings.toJson());
  }

  @override
  Future<void> clear() async {
    final SharedPreferences? preferences = await _instance();
    if (preferences == null) {
      return;
    }
    try {
      // On retire nos clés une par une plutôt que d'appeler `clear()` : les
      // préférences peuvent contenir des valeurs écrites par des plugins.
      await preferences.remove(poolConfigKey);
      await preferences.remove(mqttSettingsKey);
    } on Exception {
      // Rien à faire de plus : l'utilisateur peut réinstaller.
    }
  }
}

/// Magasin en mémoire, pour les tests et le mode démonstration.
///
/// Le comportement observable est le même que celui du magasin réel, y
/// compris la tolérance : c'est ce qui permet de tester les contrôleurs sans
/// toucher au disque.
class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore({this._poolConfig, this._mqttSettings});

  PoolConfig? _poolConfig;
  MqttSettings? _mqttSettings;

  /// Nombre d'écritures, pour vérifier qu'un contrôleur n'enregistre pas à
  /// chaque frappe de clavier.
  int writeCount = 0;

  @override
  Future<PoolConfig> loadPoolConfig() async =>
      _poolConfig ?? const PoolConfig();

  @override
  Future<void> savePoolConfig(PoolConfig config) async {
    _poolConfig = config;
    writeCount++;
  }

  @override
  Future<MqttSettings> loadMqttSettings() async =>
      _mqttSettings ?? const MqttSettings();

  @override
  Future<void> saveMqttSettings(MqttSettings settings) async {
    _mqttSettings = settings;
    writeCount++;
  }

  @override
  Future<void> clear() async {
    _poolConfig = null;
    _mqttSettings = null;
  }
}
