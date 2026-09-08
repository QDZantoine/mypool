import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/models/mqtt_settings.dart';

void main() {
  group('topics du contrat § 3', () {
    test('les topics découlent de l’identifiant', () {
      const MqttSettings settings = MqttSettings(deviceId: 'a7f3c1e9b2');

      expect(settings.topicBase, 'aquacontrol/a7f3c1e9b2');
      expect(settings.topicTelemetry, 'aquacontrol/a7f3c1e9b2/state/telemetry');
      expect(settings.topicOnline, 'aquacontrol/a7f3c1e9b2/state/online');
      expect(
        settings.topicFilterAlert,
        'aquacontrol/a7f3c1e9b2/state/alert/filter',
      );
      // Un seul filtre couvre télémétrie, présence et alerte.
      expect(settings.topicStateWildcard, 'aquacontrol/a7f3c1e9b2/state/#');
      expect(
        settings.commandTopic('cover'),
        'aquacontrol/a7f3c1e9b2/cmd/cover',
      );
    });
  });

  group('validité des réglages', () {
    test('un identifiant trop court est inutilisable', () {
      // Sur un broker public, un identifiant court rend la collision avec un
      // autre utilisateur plausible : ce serait voir bouger la bâche d’un
      // inconnu.
      expect(const MqttSettings(deviceId: 'abc').isUsable, isFalse);
      expect(const MqttSettings(deviceId: '').isUsable, isFalse);
      // 8 caractères est le minimum retenu.
      expect(const MqttSettings(deviceId: 'a7f3c1e9').isUsable, isTrue);
      expect(MqttSettings.minimumDeviceIdLength, 8);
    });

    test('une adresse vide ou un port nul sont inutilisables', () {
      expect(
        const MqttSettings(host: '', deviceId: 'a7f3c1e9b2').isUsable,
        isFalse,
      );
      expect(
        const MqttSettings(port: 0, deviceId: 'a7f3c1e9b2').isUsable,
        isFalse,
      );
    });

    test('les brokers publics sont reconnus comme tels', () {
      // Sert à afficher l’avertissement du § 6 : jamais un vrai volet sur un
      // broker public.
      expect(const MqttSettings().isPublicBroker, isTrue);
      expect(
        const MqttSettings(host: 'test.mosquitto.org').isPublicBroker,
        isTrue,
      );
      expect(const MqttSettings(host: '192.168.1.40').isPublicBroker, isFalse);
    });

    test('les défauts pointent le broker de simulation', () {
      const MqttSettings settings = MqttSettings();
      expect(settings.host, 'broker.hivemq.com');
      expect(settings.port, 1883);
      // Aucun identifiant par défaut : il doit être tiré au hasard.
      expect(settings.deviceId, '');
      expect(settings.isUsable, isFalse);
    });
  });

  group('aller-retour JSON', () {
    test('des réglages complets survivent au passage par JSON', () {
      const MqttSettings original = MqttSettings(
        host: '192.168.1.40',
        port: 8883,
        deviceId: 'a7f3c1e9b2xx',
        username: 'aquacontrol',
        password: 'secret',
      );

      final MqttSettings restored = MqttSettings.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(restored, original);
      expect(restored.hashCode, original.hashCode);
    });

    test('le mot de passe n’apparaît jamais dans toString', () {
      const MqttSettings settings = MqttSettings(
        deviceId: 'a7f3c1e9b2xx',
        password: 'motdepasse-secret',
      );
      expect(settings.toString(), isNot(contains('motdepasse')));
      expect(settings.toString(), contains('a7f3c1e9b2xx'));
    });

    test('copyWith sans argument rend un objet égal', () {
      const MqttSettings settings = MqttSettings(deviceId: 'a7f3c1e9b2xx');
      expect(settings.copyWith(), settings);
      expect(settings.copyWith(port: 8883), isNot(settings));
    });
  });

  group('JSON corrompu', () {
    test('un objet vide rend les réglages par défaut', () {
      expect(MqttSettings.fromJson(<String, dynamic>{}), const MqttSettings());
    });

    test('null, une chaîne ou une liste rendent les réglages par défaut', () {
      expect(MqttSettings.fromJson(null), const MqttSettings());
      expect(MqttSettings.fromJson('perdu'), const MqttSettings());
      expect(MqttSettings.fromJson(<int>[1]), const MqttSettings());
    });

    test('un port aberrant est borné aux ports TCP valides', () {
      expect(MqttSettings.fromJson(<String, dynamic>{'port': 0}).port, 1);
      expect(
        MqttSettings.fromJson(<String, dynamic>{'port': 99999}).port,
        65535,
      );
      expect(
        MqttSettings.fromJson(<String, dynamic>{'port': 'huit'}).port,
        1883,
      );
    });

    test('un identifiant vide reste vide plutôt que de prendre un défaut', () {
      // Un identifiant par défaut serait devinable, et donc partagé avec tous
      // les autres utilisateurs du broker public.
      expect(
        MqttSettings.fromJson(<String, dynamic>{'deviceId': '  '}).deviceId,
        '',
      );
    });
  });
}
