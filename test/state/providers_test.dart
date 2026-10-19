import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/devices/pool_device_driver.dart';
import 'package:mypool/data/devices/simulation_driver.dart';
import 'package:mypool/data/devices/unavailable_driver.dart';
import 'package:mypool/data/readings_database.dart';
import 'package:mypool/data/settings_store.dart';
import 'package:mypool/models/chemical_product.dart';
import 'package:mypool/models/dose_recommendation.dart';
import 'package:mypool/models/filtration_schedule.dart';
import 'package:mypool/models/pool_config.dart';
import 'package:mypool/models/water_reading.dart';
import 'package:mypool/state/cover_controller.dart';
import 'package:mypool/state/derived_providers.dart';
import 'package:mypool/state/providers.dart';
import 'package:mypool/state/water_readings_controller.dart';

final DateTime _start = DateTime.utc(2026, 7, 15, 10);

void main() {
  late InMemorySettingsStore settings;
  late InMemoryReadingsRepository readings;
  late ProviderContainer container;

  ProviderContainer build({PoolConfig? config}) {
    settings = InMemorySettingsStore(poolConfig: config);
    readings = InMemoryReadingsRepository();
    final ProviderContainer result = ProviderContainer(
      overrides: <Override>[
        settingsStoreProvider.overrideWithValue(settings),
        readingsRepositoryProvider.overrideWithValue(readings),
      ],
    );
    addTearDown(result.dispose);
    return result;
  }

  setUp(() {
    container = build();
  });

  group('choix du pilote', () {
    test('la simulation est le pilote par défaut', () {

      expect(container.read(deviceDriverProvider), isA<SimulationDriver>());
      expect(container.read(mqttDriverProvider), isNull);
    });

    test('la course du volet déclarée est transmise au simulateur', () async {
      await container
          .read(poolConfigProvider.notifier)
          .edit(coverTravelSeconds: 30.0);

      final SimulationDriver driver =
          container.read(deviceDriverProvider) as SimulationDriver;
      expect(driver.coverTravel, const Duration(seconds: 30));
    });

    test('un pilote non écrit échoue avec une phrase claire', () async {
      await container
          .read(poolConfigProvider.notifier)
          .edit(driver: DriverKind.homeAssistant);

      final PoolDeviceDriver driver = container.read(deviceDriverProvider);
      expect(driver, isA<UnavailableDriver>());

      await expectLater(
        driver.ping(),
        throwsA(
          isA<DeviceException>().having(
            (DeviceException e) => e.message,
            'message',
            allOf(contains('Home Assistant'), contains('réglages')),
          ),
        ),
      );
    });

    test('le pilote MQTT n’existe que si la liaison est MQTT', () async {
      await container
          .read(poolConfigProvider.notifier)
          .edit(driver: DriverKind.mqtt);

      expect(container.read(mqttDriverProvider), isNotNull);
    });

    test('renommer le bassin ne reconstruit pas le pilote', () async {
      final PoolDeviceDriver before = container.read(deviceDriverProvider);
      await container
          .read(poolConfigProvider.notifier)
          .edit(name: 'Bassin sud');

      expect(container.read(deviceDriverProvider), same(before));
    });
  });

  group('volet', () {
    test('sans consentement, aucune commande ne part', () async {
      final CoverController cover = container.read(
        coverControllerProvider.notifier,
      );
      final SimulationDriver driver =
          container.read(deviceDriverProvider) as SimulationDriver;

      expect(await cover.pressOpen(), isFalse);
      expect(driver.pulseCount, 0);
      expect(
        container.read(coverControllerProvider).refusal,
        CoverRefusal.consentMissing,
      );
    });

    test('le consentement donné débloque la commande sans reconstruire le '
        'contrôleur', () async {
      final CoverController cover = container.read(
        coverControllerProvider.notifier,
      );
      await container
          .read(poolConfigProvider.notifier)
          .setSafetyConsent(given: true);

      expect(await cover.pressOpen(), isTrue);
      await cover.release();
    });

    test('le consentement retiré rebloque immédiatement', () async {
      final CoverController cover = container.read(
        coverControllerProvider.notifier,
      );
      await container
          .read(poolConfigProvider.notifier)
          .setSafetyConsent(given: true);
      expect(await cover.pressOpen(), isTrue);
      await cover.release();

      await container
          .read(poolConfigProvider.notifier)
          .setSafetyConsent(given: false);
      expect(await cover.pressOpen(), isFalse);
    });
  });

  group('recommandations dérivées', () {
    test('aucune mesure, aucune action', () {
      expect(container.read(recommendationsProvider), isEmpty);
      expect(container.read(nextActionProvider), isNull);
      expect(container.read(waterBalanceProvider), isNull);
    });

    test('une mesure saisie produit les actions dans l’ordre métier', () async {
      await container
          .read(readingsProvider.notifier)
          .record(WaterReading(takenAt: _start, ph: 7.9, tac: 60.0));

      final List<DoseRecommendation> actions = container.read(
        recommendationsProvider,
      );

      expect(
        actions.map((DoseRecommendation a) => a.parameter).toList(),
        <WaterParameter>[WaterParameter.tac, WaterParameter.ph],
      );
      expect(container.read(nextActionProvider)?.parameter, WaterParameter.tac);
    });

    test('la dose suit la concentration déclarée', () async {
      await container
          .read(readingsProvider.notifier)
          .record(WaterReading(takenAt: _start, ph: 7.8, tac: 100.0));

      expect(
        container.read(recommendationsProvider).first.quantity,
        closeTo(1440.0, 0.001),
      );

      await container
          .read(poolConfigProvider.notifier)
          .declareProduct(
            ChemicalInventory.defaultFor(ChemicalRole.phMinus)
                .copyWith(activePercent: 60.0),
          );
      expect(
        container.read(recommendationsProvider).first.quantity,
        closeTo(2400.0, 0.001),
      );
    });

    test(
      'l’équilibre de l’eau est calculé dès que les quatre valeurs sont là',
      () async {
        await container
            .read(readingsProvider.notifier)
            .record(
              WaterReading(
                takenAt: _start,
                ph: 7.4,
                tac: 100.0,
                th: 250.0,
                temperature: 26.0,
              ),
            );

        expect(
          container.read(waterBalanceProvider)?.index,
          closeTo(-0.062, 0.001),
        );
      },
    );

    test('une eau parfaite ne produit aucune action', () async {
      await container
          .read(readingsProvider.notifier)
          .record(
            WaterReading(
              takenAt: _start,
              ph: 7.2,
              freeChlorine: 2.0,
              tac: 100.0,
              th: 250.0,
              stabilizer: 30.0,
              temperature: 26.0,
            ),
          );

      expect(container.read(recommendationsProvider), isEmpty);
    });
  });

  group('filtration dérivée', () {
    test('sans température, aucun planning', () {

      expect(container.read(filtrationPlanProvider), isNull);
      expect(container.read(waterTemperatureProvider), isNull);
    });

    test('la rotation reste calculable sans mesure', () {

      expect(container.read(turnoverProvider), const Duration(minutes: 320));
    });

    test('la température mesurée donne le planning', () async {
      await container
          .read(readingsProvider.notifier)
          .record(WaterReading(takenAt: _start, temperature: 26.0));

      final FiltrationSchedule? plan = container.read(filtrationPlanProvider);

      expect(plan?.recommendedMinutes, 780);
      expect(plan?.totalMinutes, 780);
      expect(plan?.cycles.length, 3);
    });

    test('un bassin plus grand allonge la rotation, pas la durée', () async {
      await container.read(poolConfigProvider.notifier).edit(volumeM3: 80.0);
      await container
          .read(readingsProvider.notifier)
          .record(WaterReading(takenAt: _start, temperature: 26.0));

      expect(container.read(turnoverProvider), const Duration(minutes: 640));

      expect(container.read(filtrationPlanProvider)?.recommendedMinutes, 780);
    });
  });

  group('mesure de référence', () {
    test('sans télémétrie, la saisie fait foi', () async {
      await container
          .read(readingsProvider.notifier)
          .record(WaterReading(takenAt: _start, ph: 7.5));

      expect(container.read(effectiveReadingProvider)?.ph, 7.5);
      expect(
        container.read(effectiveReadingProvider)?.source,
        MeasurementSource.manual,
      );
    });

    test('sans rien, la mesure de référence est nulle', () {
      expect(container.read(effectiveReadingProvider), isNull);
    });
  });

  group('chargement initial', () {
    test('les contrôleurs relisent ce qui était enregistré', () async {

      container = build(
        config: const PoolConfig().copyWith(
          volumeM3: 62.5,
          safetyConsentGiven: true,
        ),
      );
      await readings.insert(WaterReading(takenAt: _start, ph: 7.5));

      await container.read(poolConfigProvider.notifier).load();
      await container.read(readingsProvider.notifier).load();

      expect(container.read(poolConfigProvider).volumeM3, 62.5);
      expect(container.read(poolConfigProvider).safetyConsentGiven, isTrue);
      expect(
        container
            .read(readingsProvider.select((ReadingsState s) => s.latest))
            ?.ph,
        7.5,
      );

      expect(
        container.read(recommendationsProvider).first.quantity,
        closeTo(1125.0, 0.001),
      );
    });
  });
}
