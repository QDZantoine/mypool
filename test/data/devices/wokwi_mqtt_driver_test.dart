import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/devices/pool_device_driver.dart';
import 'package:mypool/data/devices/telemetry.dart';
import 'package:mypool/data/devices/wokwi_mqtt_driver.dart';
import 'package:mypool/models/filtration_schedule.dart';
import 'package:mypool/models/mqtt_settings.dart';

import 'fake_mqtt_transport.dart';

String telemetryJson({
  double ph = 7.24,
  double tempC = 26.4,
  double position = 0.42,
  String motion = 'idle',
  bool estimated = true,
  bool pumpOn = true,
  bool filterAlert = false,
}) {
  return jsonEncode(<String, dynamic>{
    'deviceId': 'a7f3c1e9b2xx',
    'ph': ph,
    'phRaw': 2117,
    'tempC': tempC,
    'cover': <String, dynamic>{
      'position': position,
      'motion': motion,
      'estimated': estimated,
    },
    'pump': <String, dynamic>{'on': pumpOn, 'runMinutes': 312},
    'heater': <String, dynamic>{'on': false, 'auto': true, 'setpointC': 27.0},
    'filterAlert': filterAlert,
    'uptimeS': 1834,
  });
}

void main() {
  const MqttSettings settings = MqttSettings(deviceId: 'a7f3c1e9b2xx');

  late DateTime now;
  late FakeMqttTransport transport;
  late WokwiMqttDriver driver;
  late List<Duration> delays;

  void build() {
    delays = <Duration>[];
    driver = WokwiMqttDriver(
      settings: settings,
      transport: transport,
      clock: () => now,

      delay: (Duration d) async => delays.add(d),
    );
  }

  setUp(() {
    now = DateTime.utc(2026, 7, 15, 10);
    transport = FakeMqttTransport();
    build();
  });

  Future<void> pushTelemetry(String payload) async {
    transport.deliver(settings.topicTelemetry, payload);
    await pumpEventQueue();
  }

  group('interdiction de rétention sur les commandes', () {
    test('aucune commande n’est publiée en rétention', () async {
      await driver.start();
      await driver.pulse(
        DeviceChannel.coverOpen,
        autoOff: CoverSafety.holdTimeout,
      );
      await driver.pulse(
        DeviceChannel.coverClose,
        autoOff: CoverSafety.holdTimeout,
      );
      await driver.setRelay(DeviceChannel.pump, on: true);
      await driver.setRelay(DeviceChannel.heater, on: false);

      expect(transport.commands, isNotEmpty);
      for (final PublishedMessage message in transport.published) {

        expect(
          message.retain,
          isFalse,
          reason: 'publication retenue sur ${message.topic}',
        );
      }
    });

    test('le pilote ne publie jamais sur un topic d’état', () async {
      await driver.start();
      await driver.pulse(
        DeviceChannel.coverOpen,
        autoOff: CoverSafety.holdTimeout,
      );
      for (final PublishedMessage message in transport.published) {
        expect(message.topic, contains('/cmd/'));
        expect(message.topic, isNot(contains('/state/')));
      }
    });
  });

  group('commande de bâche', () {
    test('publie « open » et « close » sur le topic de commande', () async {
      await driver.start();

      await driver.pulse(
        DeviceChannel.coverOpen,
        autoOff: CoverSafety.holdTimeout,
      );
      expect(
        transport.commands.last.topic,
        'aquacontrol/a7f3c1e9b2xx/cmd/cover',
      );
      expect(transport.commands.last.payload, 'open');

      await driver.pulse(
        DeviceChannel.coverClose,
        autoOff: CoverSafety.holdTimeout,
      );
      expect(transport.commands.last.payload, 'close');
    });

    test('la temporisation n’est PAS transmise au module', () async {
      await driver.start();
      await driver.pulse(
        DeviceChannel.coverOpen,
        autoOff: CoverSafety.holdTimeout,
      );

      final PublishedMessage sent = transport.commands.last;
      expect(sent.payload, 'open');
      expect(sent.payload, isNot(contains('1800')));
      expect(sent.payload.length, lessThan(8));
    });

    test('la garde de plafond s’applique quand même', () async {
      await driver.start();

      expect(
        () => driver.pulse(
          DeviceChannel.coverOpen,
          autoOff: const Duration(seconds: 5),
        ),
        throwsA(isA<DeviceException>()),
      );
      expect(transport.commands, isEmpty);
    });

    test('une impulsion sur la pompe ou le chauffage est refusée', () async {
      await driver.start();

      for (final DeviceChannel channel in <DeviceChannel>[
        DeviceChannel.pump,
        DeviceChannel.heater,
      ]) {
        await expectLater(
          driver.pulse(channel, autoOff: const Duration(minutes: 10)),
          throwsA(isA<DeviceException>()),
          reason: channel.name,
        );
      }
      expect(transport.commands, isEmpty);
    });

    test('une erreur de transport devient un message affichable', () async {
      await driver.start();
      transport.throwOnPublish = true;

      await expectLater(
        driver.setRelay(DeviceChannel.pump, on: true),
        throwsA(
          isA<DeviceException>()
              .having(
                (DeviceException e) => e.message,
                'message',
                allOf(contains('commande'), isNot(contains('StateError'))),
              )
              .having(
                (DeviceException e) => e.technicalDetail,
                'détail technique',
                contains('socket'),
              ),
        ),
      );
    });

    test('un volet ne se commande jamais en marche continue', () async {
      await driver.start();
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

  group('lecture d’état sans requête', () {
    test('l’état vient de la dernière télémétrie', () async {
      await driver.start();
      final int publishedBefore = transport.published.length;

      await pushTelemetry(telemetryJson(pumpOn: true, motion: 'opening'));

      expect(await driver.relayState(DeviceChannel.pump), isTrue);
      expect(await driver.relayState(DeviceChannel.coverOpen), isTrue);
      expect(await driver.relayState(DeviceChannel.coverClose), isFalse);
      expect(await driver.relayState(DeviceChannel.heater), isFalse);

      expect(transport.published.length, publishedBefore);
    });

    test('sans télémétrie, la lecture échoue avec un message clair', () async {
      await driver.start();
      await expectLater(
        driver.relayState(DeviceChannel.pump),
        throwsA(
          isA<DeviceException>().having(
            (DeviceException e) => e.message,
            'message',
            contains('pas encore transmis'),
          ),
        ),
      );
    });

    test('une télémétrie périmée n’est plus considérée comme l’état', () async {
      await driver.start();
      await pushTelemetry(telemetryJson());
      expect(driver.hasFreshTelemetry, isTrue);

      now = now.add(const Duration(seconds: 11));
      expect(driver.hasFreshTelemetry, isFalse);
      await expectLater(
        driver.relayState(DeviceChannel.pump),
        throwsA(
          isA<DeviceException>().having(
            (DeviceException e) => e.message,
            'message',
            contains('date de plus de'),
          ),
        ),
      );
    });

    test('la puissance n’est pas mesurée par ce montage', () async {
      await driver.start();
      await pushTelemetry(telemetryJson());

      expect(await driver.relayPower(DeviceChannel.pump), isNull);
    });

    test('sans fin de course, la position reste une estimation', () async {
      await driver.start();
      await pushTelemetry(telemetryJson(estimated: true, position: 1.0));

      expect(await driver.inputState(DeviceInput.coverOpenedLimit), isNull);
      expect(await driver.inputState(DeviceInput.coverClosedLimit), isNull);
    });

    test('avec une position mesurée, les butées sont déduites', () async {
      await driver.start();
      await pushTelemetry(telemetryJson(estimated: false, position: 1.0));
      expect(await driver.inputState(DeviceInput.coverOpenedLimit), isTrue);
      expect(await driver.inputState(DeviceInput.coverClosedLimit), isFalse);

      await pushTelemetry(telemetryJson(estimated: false, position: 0.0));
      expect(await driver.inputState(DeviceInput.coverClosedLimit), isTrue);
    });
  });

  group('présence du module', () {
    test('le testament MQTT fait passer le module hors ligne', () async {
      await driver.start();
      final List<bool> seen = <bool>[];
      driver.moduleOnlineStream.listen(seen.add);

      transport.deliver(settings.topicOnline, '1');
      await pumpEventQueue();
      expect(driver.isModuleOnline, isTrue);

      transport.deliver(settings.topicOnline, '0');
      await pumpEventQueue();
      expect(driver.isModuleOnline, isFalse);
      expect(seen, <bool>[true, false]);
    });

    test('recevoir une trame prouve que le module parle', () async {
      await driver.start();
      expect(driver.isModuleOnline, isFalse);
      await pushTelemetry(telemetryJson());
      expect(driver.isModuleOnline, isTrue);
    });

    test('l’alerte filtre est suivie sur son topic et dans la trame', () async {
      await driver.start();
      expect(driver.filterAlert, isFalse);

      transport.deliver(settings.topicFilterAlert, '1');
      await pumpEventQueue();
      expect(driver.filterAlert, isTrue);

      await pushTelemetry(telemetryJson(filterAlert: false));
      expect(driver.filterAlert, isFalse);
    });

    test('un topic inconnu est ignoré', () async {
      await driver.start();
      transport.deliver('aquacontrol/autre/state/telemetry', telemetryJson());
      await pumpEventQueue();

      expect(driver.lastTelemetry, isNull);
    });
  });

  group('robustesse du flux', () {
    test('une trame illisible n’éteint pas le flux', () async {
      await driver.start();
      await pushTelemetry(telemetryJson(ph: 7.2));
      expect(driver.lastTelemetry?.ph, 7.2);

      await pushTelemetry('{ceci n’est pas du JSON');
      await pushTelemetry('');

      await pushTelemetry('42');
      await pushTelemetry('"bonjour"');
      await pushTelemetry('{}');
      await pushTelemetry('[]');

      expect(driver.lastTelemetry?.ph, 7.2);
      expect(driver.hasFreshTelemetry, isTrue);

      await pushTelemetry(telemetryJson(ph: 7.5));
      expect(driver.lastTelemetry?.ph, 7.5);
    });

    test('le flux de télémétrie est diffusé aux abonnés', () async {
      await driver.start();
      final List<double?> seen = <double?>[];
      driver.telemetryStream.listen((PoolTelemetry t) => seen.add(t.ph));

      await pushTelemetry(telemetryJson(ph: 7.1));
      await pushTelemetry(telemetryJson(ph: 7.6));
      expect(seen, <double?>[7.1, 7.6]);
    });
  });

  group('reconnexion', () {
    test('l’abonnement aux états est rétabli après une reconnexion', () async {
      await driver.start();
      expect(transport.subscriptions, <String>[settings.topicStateWildcard]);

      transport.restoreConnection();
      await pumpEventQueue();

      expect(transport.subscriptions.length, 2);
      expect(transport.subscriptions.last, settings.topicStateWildcard);
    });

    test('une chute de liaison déclare le module hors ligne', () async {
      await driver.start();
      await pushTelemetry(telemetryJson());
      expect(driver.isModuleOnline, isTrue);

      transport.dropConnection();
      await pumpEventQueue();

      expect(driver.isModuleOnline, isFalse);
    });

    test('les délais de reconnexion sont progressifs et plafonnés', () async {
      await driver.start();

      transport.failuresBeforeSuccess = 3;
      transport.dropConnection();
      await pumpEventQueue();

      expect(delays.take(3).toList(), <Duration>[
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 5),
      ]);
      expect(transport.isConnected, isTrue);

      expect(transport.subscriptions.length, greaterThanOrEqualTo(2));
    });

    test('le dernier délai de la table est le plafond', () {
      expect(
        WokwiMqttDriver.reconnectBackoff.last,
        const Duration(seconds: 30),
      );

      for (int i = 1; i < WokwiMqttDriver.reconnectBackoff.length; i++) {
        expect(
          WokwiMqttDriver.reconnectBackoff[i],
          greaterThan(WokwiMqttDriver.reconnectBackoff[i - 1]),
        );
      }
    });

    test('la reconnexion s’arrête à la libération du pilote', () async {
      await driver.start();
      transport.failuresBeforeSuccess = 100;
      transport.dropConnection();
      await pumpEventQueue();
      final int attempts = transport.connectAttempts;

      await driver.dispose();
      await pumpEventQueue();

      expect(transport.connectAttempts, lessThanOrEqualTo(attempts + 1));
    });
  });

  group('ping', () {
    test('publie sur le topic de diagnostic et mesure la latence', () async {
      await driver.start();

      final Future<Duration> pending = driver.ping();
      await pumpEventQueue();
      expect(
        transport.commands.last.topic,
        'aquacontrol/a7f3c1e9b2xx/cmd/ping',
      );

      now = now.add(const Duration(milliseconds: 120));
      await pushTelemetry(telemetryJson());

      expect(await pending, const Duration(milliseconds: 120));
    });

    test('une trame antérieure à la demande ne compte pas', () async {
      await driver.start();

      await pushTelemetry(telemetryJson());

      final DateTime before = now;
      now = now.add(const Duration(seconds: 1));
      final Future<Duration> pending = driver.ping();
      await pumpEventQueue();

      now = before;
      await pushTelemetry(telemetryJson());
      bool settled = false;
      unawaited(
        pending
            .then<void>((_) => settled = true)
            .onError<Object>((_, _) => settled = true),
      );
      await pumpEventQueue();
      expect(settled, isFalse);

      now = before.add(const Duration(seconds: 2));
      await pushTelemetry(telemetryJson());
      expect(await pending, const Duration(seconds: 1));
    });

    test('sans réponse, le ping expire avec un message clair', () async {
      driver = WokwiMqttDriver(
        settings: settings,
        transport: transport,
        clock: () => now,
        delay: (Duration d) async {},

        telemetryTimeout: const Duration(milliseconds: 30),
      );
      await driver.start();

      await expectLater(
        driver.ping(),
        throwsA(
          isA<DeviceException>().having(
            (DeviceException e) => e.message,
            'message',
            contains('n’a pas répondu'),
          ),
        ),
      );
    });

    test('sans liaison, le ping échoue immédiatement', () async {

      await expectLater(
        driver.ping(),
        throwsA(
          isA<DeviceException>().having(
            (DeviceException e) => e.message,
            'message',
            contains('connexion'),
          ),
        ),
      );
    });
  });

  group('planning de filtration', () {
    test('le module refuse de mémoriser un planning, et le dit', () async {
      await driver.start();

      await expectLater(
        driver.pushFiltrationSchedule(FiltrationSchedule.empty),
        throwsA(
          isA<DeviceException>().having(
            (DeviceException e) => e.message,
            'message',
            allOf(contains('planning'), contains('téléphone')),
          ),
        ),
      );
    });

    test('l’effacement du planning n’échoue pas', () async {
      await driver.start();

      await driver.clearFiltrationSchedule();
    });
  });

  group('réglages', () {
    test('un identifiant trop court est refusé au démarrage', () async {
      driver = WokwiMqttDriver(
        settings: const MqttSettings(deviceId: 'court'),
        transport: transport,
        clock: () => now,
        delay: (Duration d) async {},
      );
      await expectLater(
        driver.start(),
        throwsA(
          isA<DeviceException>().having(
            (DeviceException e) => e.message,
            'message',
            contains('identifiant'),
          ),
        ),
      );

      expect(transport.connectAttempts, 0);
    });

    test('un pilote libéré refuse tout', () async {
      await driver.start();
      await driver.dispose();

      await expectLater(driver.start(), throwsA(isA<DeviceException>()));
      await expectLater(
        driver.setRelay(DeviceChannel.pump, on: true),
        throwsA(isA<DeviceException>()),
      );
    });
  });
}
