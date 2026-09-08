import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/devices/pool_device_driver.dart';
import 'package:mypool/data/devices/simulation_driver.dart';
import 'package:mypool/domain/filtration_planner.dart';
import 'package:mypool/models/filtration_schedule.dart';
import 'package:mypool/models/pool_config.dart';

void main() {
  /// Horloge pilotée à la main : aucun test n'attend réellement.
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

      // Le contact est fermé immédiatement après l'ordre.
      expect(await driver.relayState(DeviceChannel.coverOpen), isTrue);

      // 1 799 ms : encore fermé, la temporisation n'a pas expiré.
      advance(const Duration(milliseconds: 1799));
      expect(await driver.relayState(DeviceChannel.coverOpen), isTrue);

      // 1 801 ms : ouvert. AUCUN ordre d'arrêt n'a été envoyé entre-temps.
      // C'est le garde-fou de la règle de sécurité n° 2 : la temporisation vit
      // dans le matériel, elle ne dépend pas du réseau.
      advance(const Duration(milliseconds: 2));
      expect(await driver.relayState(DeviceChannel.coverOpen), isFalse);
    });

    test('le contact retombe même si le pilote est libéré aussitôt', () async {
      await driver.pulse(
        DeviceChannel.coverOpen,
        autoOff: CoverSafety.holdTimeout,
      );
      // L'application disparaît juste après l'ordre : le matériel doit quand
      // même arrêter le mouvement.
      await driver.dispose();
      advance(const Duration(seconds: 3));

      // Le pilote libéré refuse toute lecture, mais surtout : aucun ordre
      // d'arrêt n'était nécessaire.
      expect(
        () => driver.relayState(DeviceChannel.coverOpen),
        throwsA(isA<DeviceException>()),
      );
    });

    test('la temporisation ne peut pas dépasser 2 s sur un volet', () async {
      // Au-delà, le volet bougerait plus de deux secondes après la disparition
      // de l'application : ce n'est plus un homme mort.
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
      // Exactement 2 s reste accepté : c'est la borne haute.
      await driver.pulse(
        DeviceChannel.coverClose,
        autoOff: CoverSafety.maxCoverAutoOff,
      );
      expect(await driver.relayState(DeviceChannel.coverClose), isTrue);
    });

    test('la garde s’applique avant même de vérifier la liaison', () async {
      // Une temporisation illégale est un défaut de programmation, pas une
      // panne : elle doit être refusée même module hors ligne.
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
      // Une pompe peut légitimement tourner longtemps sur une impulsion.
      await driver.pulse(
        DeviceChannel.pump,
        autoOff: const Duration(minutes: 30),
      );
      expect(await driver.relayState(DeviceChannel.pump), isTrue);
    });

    test('un volet ne s’enclenche jamais en marche continue', () async {
      // Sans retombée automatique, le volet irait en fin de course sans
      // personne devant.
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
      // La position part de 0 (fermé).
      expect(driver.coverOpenRatio, 0.0);

      await driver.pulse(
        DeviceChannel.coverOpen,
        autoOff: const Duration(seconds: 2),
      );
      // 2 s de contact fermé, puis l'impulsion expire : le reste du temps ne
      // fait plus bouger le volet.
      advance(const Duration(seconds: 9));
      // 2 000 ms / 90 000 ms = 2,22 %
      expect(driver.coverOpenRatio, closeTo(2.0 / 90.0, 1e-9));

      // Quatre impulsions de 2 s enchaînées : 8 s de plus.
      for (int i = 0; i < 4; i++) {
        await driver.pulse(
          DeviceChannel.coverOpen,
          autoOff: const Duration(seconds: 2),
        );
        advance(const Duration(seconds: 2));
      }
      // 10 s au total sur 90 s de course = 11,1 %
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
      // 1,0 - 2/90 = 0,9778
      expect(driver.coverOpenRatio, closeTo(1.0 - 2.0 / 90.0, 1e-9));
    });

    test('la position reste bornée entre 0 et 1', () async {
      // Un maintien plus long que la course complète ne dépasse pas la butée.
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
      // 1 s d'ouverture faite.
      await driver.pulse(
        DeviceChannel.coverClose,
        autoOff: const Duration(seconds: 2),
      );
      // Le contact d'ouverture est immédiatement relâché : les deux sens ne
      // peuvent pas être actifs en même temps.
      expect(await driver.relayState(DeviceChannel.coverOpen), isFalse);
      expect(await driver.relayState(DeviceChannel.coverClose), isTrue);

      advance(const Duration(seconds: 1));
      // 1 s d'ouverture puis 1 s de fermeture : retour au point de départ.
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
      // Un relais forcé ne retombe pas avec le temps, contrairement à une
      // impulsion.
      advance(const Duration(hours: 5));
      expect(await driver.relayState(DeviceChannel.pump), isTrue);
      await driver.setRelay(DeviceChannel.pump, on: false);
      expect(await driver.relayState(DeviceChannel.pump), isFalse);
    });

    test('puissance instantanée', () async {
      // À l'arrêt, zéro watt.
      expect(await driver.relayPower(DeviceChannel.pump), 0.0);
      await driver.setRelay(DeviceChannel.pump, on: true);
      // Ordre de grandeur d'une pompe domestique.
      expect(await driver.relayPower(DeviceChannel.pump), 450.0);

      await driver.setRelay(DeviceChannel.heater, on: true);
      expect(await driver.relayPower(DeviceChannel.heater), 3000.0);

      await driver.pulse(
        DeviceChannel.coverOpen,
        autoOff: const Duration(seconds: 2),
      );
      expect(await driver.relayPower(DeviceChannel.coverOpen), 120.0);
      expect(await driver.relayPower(DeviceChannel.coverClose), 0.0);

      // Le moteur consomme dans les deux sens.
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
      // Le message affichable et le détail technique ne se mélangent pas.
      expect(error.toString(), contains('Le module ne répond pas.'));
      expect(error.toString(), isNot(contains('192.168')));
      expect(error.technicalDetail, contains('192.168'));
    });
  });

  group('fins de course', () {
    test('sans capteur, l’état est inconnu et non pas faux', () async {
      // La distinction compte : `null` fait afficher « position estimée »,
      // `false` ferait croire à une mesure.
      expect(await driver.inputState(DeviceInput.coverOpenedLimit), isNull);
      expect(await driver.inputState(DeviceInput.coverClosedLimit), isNull);
    });

    test('avec capteurs, les butées sont remontées', () async {
      final SimulationDriver sensed = SimulationDriver(
        clock: () => now,
        hasLimitSwitches: true,
      );
      // Volet fermé au départ.
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
              // Message affichable, sans trace technique.
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
      // 26 °C : 13 h de filtration.
      expect(driver.storedSchedule?.recommendedMinutes, 780);
      expect(driver.storedSchedule, schedule);

      await driver.clearFiltrationSchedule();
      expect(driver.storedSchedule, isNull);
    });
  });
}
