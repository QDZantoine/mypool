import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/settings_store.dart';
import 'package:mypool/models/chemical_product.dart';
import 'package:mypool/models/mqtt_settings.dart';
import 'package:mypool/models/pool_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PreferencesSettingsStore', () {
    late PreferencesSettingsStore store;

    Future<void> withStored(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      store = PreferencesSettingsStore(
        preferences: await SharedPreferences.getInstance(),
      );
    }

    setUp(() async {
      await withStored(<String, Object>{});
    });

    test('un stockage vide rend les valeurs par défaut', () async {

      expect(await store.loadPoolConfig(), const PoolConfig());
      expect(await store.loadMqttSettings(), const MqttSettings());
    });

    test(
      'la configuration survit à un enregistrement et une relecture',
      () async {
        final PoolConfig original = const PoolConfig().copyWith(
          name: 'Bassin nord',
          volumeM3: 62.5,
          treatment: TreatmentType.salt,
          driver: DriverKind.mqtt,
          safetyConsentGiven: true,
          inventory: ChemicalInventory.standard.withProduct(
            ChemicalInventory.defaultFor(ChemicalRole.chlorineSlow)
                .copyWith(activePercent: 56.0),
          ),
        );

        await store.savePoolConfig(original);
        final PoolConfig restored = await store.loadPoolConfig();

        expect(restored, original);

        expect(restored.safetyConsentGiven, isTrue);
        expect(
          restored.inventory.forRole(ChemicalRole.chlorineSlow).activePercent,
          56.0,
        );
      },
    );

    test('les réglages MQTT survivent à un aller-retour', () async {
      const MqttSettings original = MqttSettings(
        host: '192.168.1.40',
        port: 8883,
        deviceId: 'a7f3c1e9b2xx',
        username: 'aquacontrol',
        password: 'secret',
      );

      await store.saveMqttSettings(original);
      expect(await store.loadMqttSettings(), original);
    });

    test('un JSON corrompu rend les valeurs par défaut', () async {

      await withStored(<String, Object>{
        PreferencesSettingsStore.poolConfigKey: '{ceci n’est pas du JSON',
        PreferencesSettingsStore.mqttSettingsKey: '',
      });

      expect(await store.loadPoolConfig(), const PoolConfig());
      expect(await store.loadMqttSettings(), const MqttSettings());
    });

    test('un JSON valide mais absurde rend les valeurs par défaut', () async {
      await withStored(<String, Object>{
        PreferencesSettingsStore.poolConfigKey: jsonEncode(<String, dynamic>{
          'volumeM3': 'beaucoup',
          'treatment': 'plasma froid',
          'pumpEfficiency': 9.0,
        }),
      });

      final PoolConfig restored = await store.loadPoolConfig();
      expect(restored.volumeM3, 40.0);
      expect(restored.treatment, TreatmentType.stabilizedChlorine);

      expect(restored.pumpEfficiency, 1.0);
    });

    test(
      'un JSON qui n’est pas un objet rend les valeurs par défaut',
      () async {
        await withStored(<String, Object>{
          PreferencesSettingsStore.poolConfigKey: '42',
          PreferencesSettingsStore.mqttSettingsKey: '[1, 2, 3]',
        });

        expect(await store.loadPoolConfig(), const PoolConfig());
        expect(await store.loadMqttSettings(), const MqttSettings());
      },
    );

    test('une valeur stockée sous un autre type ne fait pas échouer '
        'l’ouverture', () async {

      await withStored(<String, Object>{
        PreferencesSettingsStore.poolConfigKey: 42,
      });

      expect(await store.loadPoolConfig(), const PoolConfig());
    });

    test('clear ne retire que les clés du projet', () async {
      await withStored(<String, Object>{'plugin.autre.cle': 'à garder'});
      await store.savePoolConfig(const PoolConfig().copyWith(volumeM3: 60.0));
      await store.saveMqttSettings(
        const MqttSettings(deviceId: 'a7f3c1e9b2xx'),
      );

      await store.clear();

      expect(await store.loadPoolConfig(), const PoolConfig());
      expect(await store.loadMqttSettings(), const MqttSettings());
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();

      expect(preferences.getString('plugin.autre.cle'), 'à garder');
    });

    test('les clés sont versionnées', () async {

      expect(PreferencesSettingsStore.poolConfigKey, endsWith('.v1'));
      expect(PreferencesSettingsStore.mqttSettingsKey, endsWith('.v1'));
    });

    test('sans instance injectée, le magasin en obtient une', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final PreferencesSettingsStore lazy = PreferencesSettingsStore();

      await lazy.savePoolConfig(const PoolConfig().copyWith(volumeM3: 55.0));
      expect((await lazy.loadPoolConfig()).volumeM3, 55.0);
      await lazy.clear();
      expect(await lazy.loadPoolConfig(), const PoolConfig());
    });
  });

  group('InMemorySettingsStore', () {
    test('se comporte comme le magasin réel', () async {
      final InMemorySettingsStore store = InMemorySettingsStore();

      expect(await store.loadPoolConfig(), const PoolConfig());
      expect(await store.loadMqttSettings(), const MqttSettings());

      final PoolConfig config = const PoolConfig().copyWith(volumeM3: 60.0);
      await store.savePoolConfig(config);
      expect(await store.loadPoolConfig(), config);

      const MqttSettings mqtt = MqttSettings(deviceId: 'a7f3c1e9b2xx');
      await store.saveMqttSettings(mqtt);
      expect(await store.loadMqttSettings(), mqtt);

      await store.clear();
      expect(await store.loadPoolConfig(), const PoolConfig());
    });

    test('compte les écritures', () async {

      final InMemorySettingsStore store = InMemorySettingsStore();
      expect(store.writeCount, 0);
      await store.savePoolConfig(const PoolConfig());
      await store.saveMqttSettings(const MqttSettings());
      expect(store.writeCount, 2);
    });

    test('accepte un état initial', () async {
      final InMemorySettingsStore store = InMemorySettingsStore(
        poolConfig: const PoolConfig().copyWith(volumeM3: 80.0),
        mqttSettings: const MqttSettings(deviceId: 'préréglé1234'),
      );
      expect((await store.loadPoolConfig()).volumeM3, 80.0);
      expect((await store.loadMqttSettings()).deviceId, 'préréglé1234');
    });
  });
}
