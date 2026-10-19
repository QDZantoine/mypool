import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/mqtt_settings.dart';
import '../models/pool_config.dart';

abstract class SettingsStore {
  Future<PoolConfig> loadPoolConfig();

  Future<void> savePoolConfig(PoolConfig config);

  Future<MqttSettings> loadMqttSettings();

  Future<void> saveMqttSettings(MqttSettings settings);

  Future<void> clear();
}

class PreferencesSettingsStore implements SettingsStore {
  PreferencesSettingsStore({this._preferences});

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

    } on Object {

      return null;
    }
  }

  Future<Object?> _readJson(String key) async {
    final SharedPreferences? preferences = await _instance();
    if (preferences == null) {
      return null;
    }
    String? raw;
    try {
      raw = preferences.getString(key);

    } on Object {
      return null;
    }
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      return jsonDecode(raw);
    } on FormatException {

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

      await preferences.remove(poolConfigKey);
      await preferences.remove(mqttSettingsKey);
    } on Exception {

    }
  }
}

class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore({this._poolConfig, this._mqttSettings});

  PoolConfig? _poolConfig;
  MqttSettings? _mqttSettings;

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
