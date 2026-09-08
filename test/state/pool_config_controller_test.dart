import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/settings_store.dart';
import 'package:mypool/models/chemical_product.dart';
import 'package:mypool/models/mqtt_settings.dart';
import 'package:mypool/models/pool_config.dart';
import 'package:mypool/state/pool_config_controller.dart';

void main() {
  late InMemorySettingsStore store;
  late PoolConfigController controller;

  setUp(() {
    store = InMemorySettingsStore();
    controller = PoolConfigController(store: store);
  });

  tearDown(() {
    controller.dispose();
  });

  group('chargement', () {
    test('l’état initial est la piscine par défaut, pas un état d’attente', () {
      // L'application doit être utilisable dès la première image : 40 m3 au
      // chlore stabilisé, en simulation.
      expect(controller.state, const PoolConfig());
      expect(controller.state.volumeM3, 40.0);
      expect(controller.isLoaded, isFalse);
    });

    test('load remplace l’état par la valeur enregistrée', () async {
      store = InMemorySettingsStore(
        poolConfig: const PoolConfig().copyWith(volumeM3: 62.5),
      );
      controller = PoolConfigController(store: store);

      await controller.load();

      expect(controller.state.volumeM3, 62.5);
      expect(controller.isLoaded, isTrue);
    });

    test('load sur un stockage vide garde les valeurs par défaut', () async {
      await controller.load();
      expect(controller.state, const PoolConfig());
      expect(controller.isLoaded, isTrue);
    });
  });

  group('modification', () {
    test('edit ne touche que le champ demandé et enregistre', () async {
      await controller.edit(volumeM3: 60.0);

      expect(controller.state.volumeM3, 60.0);
      // Les autres champs gardent leur valeur : un écran qui ne saisit qu'un
      // champ ne doit pas réinitialiser les autres.
      expect(controller.state.treatment, TreatmentType.stabilizedChlorine);
      expect(controller.state.pumpFlowM3PerHour, 10.0);
      expect(store.writeCount, 1);
      expect((await store.loadPoolConfig()).volumeM3, 60.0);
    });

    test('replace écrase tout et enregistre', () async {
      final PoolConfig config = const PoolConfig().copyWith(
        name: 'Bassin nord',
        treatment: TreatmentType.salt,
      );
      await controller.replace(config);

      expect(controller.state, config);
      expect(await store.loadPoolConfig(), config);
    });

    test('useVolumeFromDimensions reprend le calcul des dimensions', () async {
      await controller.edit(lengthM: 10.0, widthM: 5.0, averageDepthM: 1.5);
      await controller.useVolumeFromDimensions();

      // 10 x 5 x 1,5 = 75 m3
      expect(controller.state.volumeM3, closeTo(75.0, 1e-9));
    });

    test(
      'declareProduct change la concentration utilisée pour les doses',
      () async {
        // C'est ce qui rend les doses justes : un chlore à 56 % pris pour du
        // 90 % donne un tiers de dose en moins.
        await controller.declareProduct(
          ChemicalInventory.defaultFor(ChemicalRole.chlorineSlow)
              .copyWith(activePercent: 56.0, label: 'Mes galets'),
        );

        final ChemicalProduct declared = controller.state.inventory.forRole(
          ChemicalRole.chlorineSlow,
        );
        expect(declared.activePercent, 56.0);
        expect(declared.label, 'Mes galets');
        // Les autres produits ne bougent pas.
        expect(
          controller.state.inventory
              .forRole(ChemicalRole.phMinus)
              .activePercent,
          100.0,
        );
        // Et la déclaration est persistée.
        expect(
          (await store.loadPoolConfig()).inventory
              .forRole(ChemicalRole.chlorineSlow)
              .activePercent,
          56.0,
        );
      },
    );
  });

  group('consentement de sécurité', () {
    test('il est refusé par défaut', () {
      expect(controller.state.safetyConsentGiven, isFalse);
    });

    test('il est persisté une fois donné', () async {
      // Le redemander à chaque ouverture le transformerait en clic réflexe.
      await controller.setSafetyConsent(given: true);

      expect(controller.state.safetyConsentGiven, isTrue);
      expect((await store.loadPoolConfig()).safetyConsentGiven, isTrue);
    });

    test('il peut être retiré', () async {
      await controller.setSafetyConsent(given: true);
      await controller.setSafetyConsent(given: false);

      expect(controller.state.safetyConsentGiven, isFalse);
      expect((await store.loadPoolConfig()).safetyConsentGiven, isFalse);
    });
  });

  group('réglages MQTT', () {
    late MqttSettingsController mqtt;

    setUp(() {
      mqtt = MqttSettingsController(store: store);
    });

    tearDown(() {
      mqtt.dispose();
    });

    test('l’état initial pointe le broker de simulation, sans identifiant', () {
      expect(mqtt.state.host, MqttSettings.defaultHost);
      // Aucun identifiant par défaut : il doit être tiré au hasard.
      expect(mqtt.state.deviceId, '');
      expect(mqtt.state.isUsable, isFalse);
    });

    test('edit enregistre et ne touche que le champ demandé', () async {
      await mqtt.edit(deviceId: 'a7f3c1e9b2xx');

      expect(mqtt.state.deviceId, 'a7f3c1e9b2xx');
      expect(mqtt.state.host, MqttSettings.defaultHost);
      expect(mqtt.state.isUsable, isTrue);
      expect((await store.loadMqttSettings()).deviceId, 'a7f3c1e9b2xx');
    });

    test('load relit la valeur enregistrée', () async {
      await mqtt.replace(
        const MqttSettings(host: '192.168.1.40', deviceId: 'a7f3c1e9b2xx'),
      );

      final MqttSettingsController fresh = MqttSettingsController(store: store);
      addTearDown(fresh.dispose);
      await fresh.load();

      expect(fresh.state.host, '192.168.1.40');
      expect(fresh.state.deviceId, 'a7f3c1e9b2xx');
    });

    test('les réglages du bassin et du broker sont indépendants', () async {
      // On remplace un broker sans toucher au volume du bassin.
      await controller.edit(volumeM3: 60.0);
      await mqtt.edit(deviceId: 'a7f3c1e9b2xx');

      expect((await store.loadPoolConfig()).volumeM3, 60.0);
      expect((await store.loadMqttSettings()).deviceId, 'a7f3c1e9b2xx');
    });
  });
}
