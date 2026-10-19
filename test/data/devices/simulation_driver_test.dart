import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/devices/pool_device_driver.dart';
import 'package:mypool/data/devices/simulation_driver.dart';
import 'package:mypool/domain/filtration_planner.dart';
import 'package:mypool/models/filtration_schedule.dart';
import 'package:mypool/models/pool_config.dart';

void main() {

  late DateTime now;
  late SimulationDriver driver;

  setUp(() {
    now = DateTime.utc(2026, 7, 15, 10);
    driver = SimulationDriver(clock: () => now);
  });

  void advance(Duration duration) {
    now = now.add(duration);
  }

  group('règle de sécurité n° 2 : l’impulsion retombe toute seule', () {
    test('un contact fermé 1 800 ms est ouvert à 1 801 ms', () async {
      await driver.pulse(
        DeviceChannel.coverOpen,
        autoOff: CoverSafety.holdTimeout,
      );

      expect(await driver.relayState(DeviceChannel.coverOpen), isTrue);

      advance(const Duration(milliseconds: 1799));
      expect(await driver.relayState(DeviceChannel.coverOpen), isTrue);

      advance(const Duration(milliseconds: 2));
      expect(await driver.relayState(DeviceChannel.coverOpen), isFalse);
    });

    test('le contact retombe même si le pilote est libéré aussitôt', () async {
      await driver.pulse(
        DeviceChannel.coverOpen,
        autoOff: CoverSafety.holdTimeout,
      );

      await driver.dispose();
      advance(const Duration(seconds: 3));

      expect(
        () => driver.relayState(DeviceChannel.coverOpen),
        throwsA(isA<DeviceException>()),
      );
    });

    test('la temporisation ne peut pas dépasser 2 s sur un volet', () async {

      expect(
        () => driver.pulse(
          DeviceChannel.coverOpen,
          autoOff: const Duration(seconds: 3),
        ),
        throwsA(isA<DeviceException>()),
      );
      expect(
        () => driver.pulse(DeviceChannel.coverClose, autoOff: Duration.zero),
        throwsA(isA<DeviceException>()),
      );

      await driver.pulse(
        DeviceChannel.coverClose,
        autoOff: CoverSafety.maxCoverAutoOff,
      );
      expect(await driver.relayState(DeviceChannel.coverClose), isTrue);
    });

    test('la garde s’applique avant même de vérifier la liaison', () async {

      driver.setOnline(false);
      expect(
        () => driver.pulse(
          DeviceChannel.coverOpen,
          autoOff: const Duration(seconds: 10),
        ),
        throwsA(isA<DeviceException>()),
      );
    });

    test('la pompe n’est pas soumise à la limite du volet', () async {

      await driver.pulse(
        DeviceChannel.pump,
        autoOff: const Duration(minutes: 30),
      );
      expect(await driver.relayState(DeviceChannel.pump), isTrue);
    });

    test('un volet ne s’enclenche jamais en marche continue', () async {

      expect(
        () => driver.setRelay(DeviceChannel.coverOpen, on: true),
        throwsA(isA<DeviceException>()),
      );
      expect(
        () => driver.setRelay(DeviceChannel.coverClose, on: true),
        throwsA(isA<DeviceException>()),
      );
    });
  });

  group('estimation de la position', () {
    test('9 s d’ouverture sur une course de 90 s font 10 %', () async {

      expect(driver.coverOpenRatio, 0.0);

      await driver.pulse(
        DeviceChannel.coverOpen,
        autoOff: const Duration(seconds: 2),
      );

      advance(const Duration(seconds: 9));

      expect(driver.coverOpenRatio, closeTo(2.0 / 90.0, 1e-9));

      for (int i = 0; i < 4; i++) {
        await driver.pulse(
          DeviceChannel.coverOpen,
          autoOff: const Duration(seconds: 2),
        );
        advance(const Duration(seconds: 2));
      }

      expect(driver.coverOpenRatio, closeTo(10.0 / 90.0, 1e-9));
    });

    test('la fermeture fait décroître la position', () async {
      driver.calibrateCover(open: true);
      expect(driver.coverOpenRatio, 1.0);

      await driver.pulse(
        DeviceChannel.coverClose,
        autoOff: const Duration(seconds: 2),
      );
      advance(const Duration(seconds: 2));

      expect(driver.coverOpenRatio, closeTo(1.0 - 2.0 / 90.0, 1e-9));
    });

    test('la position reste bornée entre 0 et 1', () async {

      for (int i = 0; i < 60; i++) {
        await driver.pulse(
          DeviceChannel.coverOpen,
          autoOff: const Duration(seconds: 2),
        );
        advance(const Duration(seconds: 2));
      }
      expect(driver.coverOpenRatio, 1.0);

      for (int i = 0; i < 60; i++) {
        await driver.pulse(
          DeviceChannel.coverClose,
          autoOff: const Duration(seconds: 2),
        );
        advance(const Duration(seconds: 2));
      }
      expect(driver.coverOpenRatio, 0.0);
    });

    test('un ordre inverse annule le sens précédent', () async {
      await driver.pulse(
        DeviceChannel.coverOpen,
        autoOff: const Duration(seconds: 2),
      );
      advance(const Duration(seconds: 1));

      await driver.pulse(
        DeviceChannel.coverClose,
        autoOff: const Duration(seconds: 2),
      );

      expect(await driver.relayState(DeviceChannel.coverOpen), isFalse);
      expect(await driver.relayState(DeviceChannel.coverClose), isTrue);

      advance(const Duration(seconds: 1));

      expect(driver.coverOpenRatio, closeTo(0.0, 1e-9));
    });

    test('une course nulle ne fait pas diverger la position', () async {
      final SimulationDriver flat = SimulationDriver(
        clock: () => now,
        coverTravel: Duration.zero,
      );
      await flat.pulse(
        DeviceChannel.coverOpen,
        autoOff: const Duration(seconds: 2),
      );
      advance(const Duration(seconds: 2));
      expect(flat.coverOpenRatio, 0.0);
    });
  });

  group('relais de la pompe', () {
    test('marche forcée et arrêt', () async {
      expect(await driver.relayState(DeviceChannel.pump), isFalse);
      await driver.setRelay(DeviceChannel.pump, on: true);
      expect(await driver.relayState(DeviceChannel.pump), isTrue);

      advance(const Duration(hours: 5));
      expect(await driver.relayState(DeviceChannel.pump), isTrue);
      await driver.setRelay(DeviceChannel.pump, on: false);
      expect(await driver.relayState(DeviceChannel.pump), isFalse);
    });

    test('puissance instantanée', () async {

      expect(await driver.relayPower(DeviceChannel.pump), 0.0);
      await driver.setRelay(DeviceChannel.pump, on: true);

      expect(await driver.relayPower(DeviceChannel.pump), 450.0);

      await driver.setRelay(DeviceChannel.heater, on: true);
      expect(await driver.relayPower(DeviceChannel.heater), 3000.0);

      await driver.pulse(
        DeviceChannel.coverOpen,
        autoOff: const Duration(seconds: 2),
      );
      expect(await driver.relayPower(DeviceChannel.coverOpen), 120.0);
      expect(await driver.relayPower(DeviceChannel.coverClose), 0.0);

      await driver.pulse(
        DeviceChannel.coverClose,
        autoOff: const Duration(seconds: 2),
      );
      expect(await driver.relayPower(DeviceChannel.coverClose), 120.0);
      expect(await driver.relayPower(DeviceChannel.coverOpen), 0.0);
    });

    test('l’erreur matérielle reste lisible en journal', () {
      const DeviceException error = DeviceException(
        'Le module ne répond pas.',
        technicalDetail: 'timeout 5 s sur 192.168.1.42',
      );

      expect(error.toString(), contains('Le module ne répond pas.'));
      expect(error.toString(), isNot(contains('192.168')));
      expect(error.technicalDetail, contains('192.168'));
    });
  });

  group('fins de course', () {
    test('sans capteur, l’état est inconnu et non pas faux', () async {

      expect(await driver.inputState(DeviceInput.coverOpenedLimit), isNull);
      expect(await driver.inputState(DeviceInput.coverClosedLimit), isNull);
    });

    test('avec capteurs, les butées sont remontées', () async {
      final SimulationDriver sensed = SimulationDriver(
        clock: () => now,
        hasLimitSwitches: true,
      );

      expect(await sensed.inputState(DeviceInput.coverClosedLimit), isTrue);
      expect(await sensed.inputState(DeviceInput.coverOpenedLimit), isFalse);

      sensed.calibrateCover(open: true);
      expect(await sensed.inputState(DeviceInput.coverOpenedLimit), isTrue);
      expect(await sensed.inputState(DeviceInput.coverClosedLimit), isFalse);
    });
  });

  group('liaison', () {
    test('ping rend la latence simulée', () async {
      expect(await driver.ping(), const Duration(milliseconds: 20));
    });

    test('hors ligne, chaque opération donne un message en français', () async {
      driver.setOnline(false);
      expect(driver.isOnline, isFalse);

      for (final Future<Object?> Function() operation
          in <Future<Object?> Function()>[
            driver.ping,
            () => driver.relayState(DeviceChannel.pump),
            () => driver.relayPower(DeviceChannel.pump),
            () => driver.inputState(DeviceInput.coverClosedLimit),
            () => driver.setRelay(DeviceChannel.pump, on: true),
            () => driver.pulse(
              DeviceChannel.coverOpen,
              autoOff: CoverSafety.holdTimeout,
            ),
            () => driver.clearFiltrationSchedule(),
          ]) {
        await expectLater(
          operation(),
          throwsA(
            isA<DeviceException>().having(
              (DeviceException e) => e.message,
              'message',

              allOf(contains('module'), isNot(contains('Exception'))),
            ),
          ),
        );
      }

      driver.setOnline(true);
      expect(await driver.ping(), const Duration(milliseconds: 20));
    });
  });

  group('planning de filtration', () {
    test('le planning est écrit dans le module simulé', () async {
      final FiltrationSchedule schedule = FiltrationPlanner.plan(
        config: const PoolConfig(),
        temperatureC: 26.0,
      );

      expect(driver.storedSchedule, isNull);
      await driver.pushFiltrationSchedule(schedule);

      expect(driver.storedSchedule?.recommendedMinutes, 780);
      expect(driver.storedSchedule, schedule);

      await driver.clearFiltrationSchedule();
      expect(driver.storedSchedule, isNull);
    });
  });
}
