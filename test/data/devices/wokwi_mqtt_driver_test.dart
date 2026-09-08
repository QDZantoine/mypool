import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/devices/pool_device_driver.dart';
import 'package:mypool/data/devices/telemetry.dart';
import 'package:mypool/data/devices/wokwi_mqtt_driver.dart';
import 'package:mypool/models/filtration_schedule.dart';
import 'package:mypool/models/mqtt_settings.dart';

import 'fake_mqtt_transport.dart';

/// Trame conforme au § 3.1 de l'addendum.
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
      // Les délais de reconnexion sont enregistrés puis ignorés : aucun test
      // n'attend réellement.
      delay: (Duration d) async => delays.add(d),
    );
  }

  setUp(() {
    now = DateTime.utc(2026, 7, 15, 10);
    transport = FakeMqttTransport();
    build();
  });

  /// Livre une trame et laisse le flux se propager.
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
        // Un « open » retenu par le broker serait relivré au module à sa
        // prochaine connexion et relancerait un mouvement sans personne
        // devant la piscine.
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

      // Ce n'est pas un oubli : le délai de garde vit dans le firmware.
      // Transmettre la temporisation ferait dépendre l'arrêt d'un ordre passé
      // par le réseau, ce qui n'est pas une sécurité.
      final PublishedMessage sent = transport.commands.last;
      expect(sent.payload, 'open');
      expect(sent.payload, isNot(contains('1800')));
      expect(sent.payload.length, lessThan(8));
    });

    test('la garde de plafond s’applique quand même', () async {
      await driver.start();
      // Une temporisation illégale reste refusée, même si elle n'est pas
      // envoyée : c'est un défaut de programmation de l'appelant.
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
      // Le contrat § 3.2 n'expose pas d'impulsion temporisée pour ces deux
      // relais : ils se commandent en marche/arrêt.
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
      // Une exception technique ne doit jamais atteindre l'interface.
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

      // Aucune requête n'a été envoyée pour lire l'état.
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

      // Le module publie toutes les 2 s : à 11 s, quatre trames ont été
      // perdues, l'état affiché ne fait plus foi.
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
      // `null` le dit, plutôt qu'un zéro qui passerait pour une mesure.
      expect(await driver.relayPower(DeviceChannel.pump), isNull);
    });

    test('sans fin de course, la position reste une estimation', () async {
      await driver.start();
      await pushTelemetry(telemetryJson(estimated: true, position: 1.0));
      // Le firmware publie `estimated: true` : il n'a pas de capteur.
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

      // « 0 » publié par le broker au nom de l'ESP32 disparu.
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
      // Les topics d'une autre installation ne doivent rien changer.
      expect(driver.lastTelemetry, isNull);
    });
  });

  group('robustesse du flux', () {
    test('une trame illisible n’éteint pas le flux', () async {
      await driver.start();
      await pushTelemetry(telemetryJson(ph: 7.2));
      expect(driver.lastTelemetry?.ph, 7.2);

      // Sur un broker public, n'importe qui peut publier n'importe quoi.
      await pushTelemetry('{ceci n’est pas du JSON');
      await pushTelemetry('');
      // Un JSON valide qui n'est pas une trame : il se décoderait en trame
      // vide et effacerait le dernier état connu.
      await pushTelemetry('42');
      await pushTelemetry('"bonjour"');
      await pushTelemetry('{}');
      await pushTelemetry('[]');
      // La dernière trame valide reste en place.
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

      // Un abonnement ne survit pas à une déconnexion : sans ce
      // rétablissement, l'application resterait muette après un retour de
      // réseau.
      expect(transport.subscriptions.length, 2);
      expect(transport.subscriptions.last, settings.topicStateWildcard);
    });

    test('une chute de liaison déclare le module hors ligne', () async {
      await driver.start();
      await pushTelemetry(telemetryJson());
      expect(driver.isModuleOnline, isTrue);

      transport.dropConnection();
      await pumpEventQueue();

      // L'état affiché doit dire « hors ligne » plutôt que rester figé sur la
      // dernière valeur connue.
      expect(driver.isModuleOnline, isFalse);
    });

    test('les délais de reconnexion sont progressifs et plafonnés', () async {
      await driver.start();
      // Le broker refuse les trois prochaines tentatives.
      transport.failuresBeforeSuccess = 3;
      transport.dropConnection();
      await pumpEventQueue();

      // 1 s, 2 s, 5 s puis succès : on ne martèle pas un broker en panne.
      expect(delays.take(3).toList(), <Duration>[
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 5),
      ]);
      expect(transport.isConnected, isTrue);
      // Et l'abonnement est rétabli.
      expect(transport.subscriptions.length, greaterThanOrEqualTo(2));
    });

    test('le dernier délai de la table est le plafond', () {
      expect(
        WokwiMqttDriver.reconnectBackoff.last,
        const Duration(seconds: 30),
      );
      // Table croissante : un délai qui redescendrait annulerait l'intérêt.
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
      // Plus aucune tentative après libération.
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

      // Le module republie sa télémétrie 120 ms plus tard.
      now = now.add(const Duration(milliseconds: 120));
      await pushTelemetry(telemetryJson());

      expect(await pending, const Duration(milliseconds: 120));
    });

    test('une trame antérieure à la demande ne compte pas', () async {
      await driver.start();
      // Une trame reçue AVANT le ping ne prouve pas que la liaison fonctionne
      // maintenant.
      await pushTelemetry(telemetryJson());

      final DateTime before = now;
      now = now.add(const Duration(seconds: 1));
      final Future<Duration> pending = driver.ping();
      await pumpEventQueue();

      // Une trame horodatée dans le passé est ignorée par l'attente.
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

      // Une trame postérieure la débloque.
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
        // Délai raccourci : le test n'attend pas six secondes.
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
      // Pas de start() : le transport n'est pas connecté.
      await expectLater(
        driver.ping(),
        throwsA(
          isA<DeviceException>().having(
            (DeviceException e) => e.message,
            'message',
            contains('Pas de liaison'),
          ),
        ),
      );
    });
  });

  group('planning de filtration', () {
    test('le module refuse de mémoriser un planning, et le dit', () async {
      await driver.start();
      // Limite assumée du § 8.1 : lever une erreur explicite vaut mieux que
      // faire croire que la piscine filtrera téléphone éteint.
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
      // Aucun planning n'a jamais été écrit : échouer ici empêcherait un
      // changement de matériel de se terminer.
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
      // Aucune connexion tentée sur des réglages inutilisables.
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
