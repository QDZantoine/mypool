import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/devices/pool_device_driver.dart';
import 'package:mypool/data/devices/unavailable_driver.dart';
import 'package:mypool/models/filtration_schedule.dart';
import 'package:mypool/models/pool_config.dart';

void main() {
  group('pilote non disponible', () {
    test('chaque type de liaison a un libellé affichable', () async {
      // Le message doit nommer la liaison choisie, sinon l'utilisateur ne sait
      // pas quoi changer dans les réglages.
      const Map<DriverKind, String> expected = <DriverKind, String>{
        DriverKind.localModule: 'module local',
        DriverKind.homeAssistant: 'Home Assistant',
        DriverKind.mqtt: 'MQTT',
        DriverKind.simulation: 'simulation',
      };

      for (final DriverKind kind in DriverKind.values) {
        await expectLater(
          UnavailableDriver(kind).ping(),
          throwsA(
            isA<DeviceException>().having(
              (DeviceException e) => e.message,
              'message pour ${kind.name}',
              contains(expected[kind]!),
            ),
          ),
        );
      }
    });

    test('toute opération échoue avec une phrase en français', () async {
      const UnavailableDriver driver = UnavailableDriver(
        DriverKind.homeAssistant,
      );

      final List<Future<Object?>> operations = <Future<Object?>>[
        driver.pulse(DeviceChannel.coverOpen, autoOff: CoverSafety.holdTimeout),
        driver.setRelay(DeviceChannel.pump, on: true),
        driver.relayState(DeviceChannel.pump),
        driver.relayPower(DeviceChannel.pump),
        driver.inputState(DeviceInput.coverClosedLimit),
        driver.ping(),
        driver.pushFiltrationSchedule(FiltrationSchedule.empty),
      ];

      for (final Future<Object?> operation in operations) {
        await expectLater(
          operation,
          throwsA(
            isA<DeviceException>()
                .having(
                  (DeviceException e) => e.message,
                  'message',
                  allOf(
                    contains('n’est pas encore disponible'),
                    isNot(contains('Exception')),
                  ),
                )
                .having(
                  (DeviceException e) => e.technicalDetail,
                  'détail technique',
                  contains('homeAssistant'),
                ),
          ),
        );
      }
    });

    test('la garde de sécurité passe avant l’indisponibilité', () async {
      // Une temporisation illégale reste un défaut de programmation, même sur
      // un pilote qui ne pilote rien.
      const UnavailableDriver driver = UnavailableDriver(
        DriverKind.localModule,
      );
      await expectLater(
        driver.pulse(
          DeviceChannel.coverOpen,
          autoOff: const Duration(seconds: 10),
        ),
        throwsA(
          isA<DeviceException>().having(
            (DeviceException e) => e.message,
            'message',
            contains('refusée par sécurité'),
          ),
        ),
      );
    });

    test('l’effacement du planning et la libération n’échouent pas', () async {
      // Échouer ici empêcherait un changement de matériel de se terminer.
      const UnavailableDriver driver = UnavailableDriver(DriverKind.mqtt);
      await driver.clearFiltrationSchedule();
      await driver.dispose();
    });
  });
}
