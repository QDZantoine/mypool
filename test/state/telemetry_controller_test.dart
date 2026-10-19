import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/devices/pool_device_driver.dart';
import 'package:mypool/data/devices/wokwi_mqtt_driver.dart';
import 'package:mypool/models/mqtt_settings.dart';
import 'package:mypool/models/water_reading.dart';
import 'package:mypool/state/telemetry_controller.dart';

import '../data/devices/fake_mqtt_transport.dart';

const MqttSettings _settings = MqttSettings(deviceId: 'a7f3c1e9b2xx');

String _telemetry({double ph = 7.24, double tempC = 26.4}) {
  return jsonEncode(<String, dynamic>{
    'deviceId': 'a7f3c1e9b2xx',
    'ph': ph,
    'tempC': tempC,
    'cover': <String, dynamic>{
      'position': 0.42,
      'motion': 'idle',
      'estimated': true,
    },
    'pump': <String, dynamic>{'on': true, 'runMinutes': 312},
    'filterAlert': false,
  });
}

void main() {
  late DateTime now;
  late FakeMqttTransport transport;
  late WokwiMqttDriver driver;
  late TelemetryController controller;

  late List<WaterReading> recorded;

  WaterReading? storedSensorReading;

  void build({bool withDriver = true}) {
    recorded = <WaterReading>[];
    controller = TelemetryController(
      driver: withDriver ? driver : null,
      clock: () => now,
      onSample: (WaterReading reading) async {
        recorded.add(reading);
        storedSensorReading = reading;
        return reading;
      },
      lastSensorReading: () async => storedSensorReading,
    );
  }

  setUp(() {
    now = DateTime.utc(2026, 7, 15, 10);
    storedSensorReading = null;
    transport = FakeMqttTransport();
    driver = WokwiMqttDriver(
      settings: _settings,
      transport: transport,
      clock: () => now,
      delay: (Duration d) async {},
    );
    build();
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> deliver(String payload) async {
    transport.deliver(_settings.topicTelemetry, payload);
    await pumpEventQueue();
  }

  group('état de la liaison', () {
    test('l’état initial est hors ligne, sans erreur', () {
      expect(controller.state.isModuleOnline, isFalse);
      expect(controller.state.isFresh, isFalse);
      expect(controller.state.hasLiveValues, isFalse);
      expect(controller.state.errorMessage, isNull);
    });

    test('une trame reçue met l’état en direct', () async {
      await controller.start();
      await deliver(_telemetry(ph: 7.24, tempC: 26.4));

      expect(controller.state.isModuleOnline, isTrue);
      expect(controller.state.isFresh, isTrue);
      expect(controller.state.hasLiveValues, isTrue);
      expect(controller.state.livePh, 7.24);
      expect(controller.state.liveTemperatureC, 26.4);
      expect(controller.framesReceived, 1);
    });

    test('le testament du module coupe la fraîcheur', () async {
      await controller.start();
      await deliver(_telemetry());
      expect(controller.state.isFresh, isTrue);

      transport.deliver(_settings.topicOnline, '0');
      await pumpEventQueue();

      expect(controller.state.isModuleOnline, isFalse);
      expect(controller.state.isFresh, isFalse);
      expect(controller.state.hasLiveValues, isFalse);

      expect(controller.state.telemetry, isNotNull);
    });

    test('refreshFreshness fait périmer un état trop vieux', () async {
      await controller.start();
      await deliver(_telemetry());
      expect(controller.state.isFresh, isTrue);

      now = now.add(const Duration(seconds: 11));
      controller.refreshFreshness();

      expect(controller.state.isFresh, isFalse);
      expect(controller.state.livePh, isNull);
    });

    test(
      'une liaison qui ne s’ouvre pas laisse un message affichable',
      () async {
        transport.failuresBeforeSuccess = 1;
        await controller.start();

        expect(controller.state.errorMessage, isNotNull);
        expect(controller.state.errorMessage, isNot(contains('Exception')));
        expect(controller.state.isModuleOnline, isFalse);
      },
    );

    test('l’alerte filtre est suivie', () async {
      await controller.start();
      await deliver(
        jsonEncode(<String, dynamic>{'ph': 7.2, 'filterAlert': true}),
      );
      expect(controller.state.filterAlert, isTrue);
    });
  });

  group('échantillonnage automatique (addendum § 5)', () {
    test('la première trame entre dans l’historique', () async {
      await controller.start();
      await deliver(_telemetry(ph: 7.24, tempC: 26.4));

      expect(recorded.length, 1);
      expect(recorded.first.ph, 7.24);
      expect(recorded.first.temperature, 26.4);

      expect(recorded.first.source, MeasurementSource.sensor);
      expect(controller.samplesRecorded, 1);
    });

    test('43 200 trames par jour ne donnent pas 43 200 lignes', () async {
      await controller.start();

      for (int step = 0; step < 1800; step++) {
        now = now.add(const Duration(seconds: 2));
        await deliver(_telemetry(ph: 7.24, tempC: 26.4));
      }

      expect(controller.framesReceived, 1800);

      expect(recorded.length, 1);
    });

    test('une variation suffisante après une heure est enregistrée', () async {
      await controller.start();
      await deliver(_telemetry(ph: 7.20, tempC: 26.0));
      expect(recorded.length, 1);

      now = now.add(const Duration(minutes: 30));
      await deliver(_telemetry(ph: 7.50, tempC: 26.0));
      expect(recorded.length, 1);

      now = now.add(const Duration(minutes: 31));
      await deliver(_telemetry(ph: 7.50, tempC: 26.0));
      expect(recorded.length, 2);
      expect(recorded.last.ph, 7.50);
    });

    test('la référence survit à un redémarrage de l’application', () async {

      storedSensorReading = WaterReading(
        takenAt: now.subtract(const Duration(minutes: 10)),
        ph: 7.20,
        temperature: 26.0,
        source: MeasurementSource.sensor,
      );

      await controller.start();
      await deliver(_telemetry(ph: 7.80, tempC: 26.0));

      expect(recorded, isEmpty);
    });

    test('une trame sans mesure n’est jamais enregistrée', () async {
      await controller.start();
      await deliver(
        jsonEncode(<String, dynamic>{
          'pump': <String, dynamic>{'on': true},
        }),
      );

      expect(controller.framesReceived, 1);
      expect(recorded, isEmpty);
    });

    test('si l’écriture échoue, la référence n’avance pas', () async {

      controller.dispose();
      controller = TelemetryController(
        driver: driver,
        clock: () => now,

        onSample: (WaterReading reading) async => null,
        lastSensorReading: () async => null,
      );

      await controller.start();
      await deliver(_telemetry(ph: 7.2));
      expect(controller.samplesRecorded, 0);

      now = now.add(const Duration(hours: 2));
      await deliver(_telemetry(ph: 7.2));
      expect(controller.samplesRecorded, 0);
      expect(controller.framesReceived, 2);
    });
  });

  group('test de liaison', () {
    test('testConnection rend la latence', () async {
      await controller.start();

      final Future<Duration> pending = controller.testConnection();
      await pumpEventQueue();
      now = now.add(const Duration(milliseconds: 90));
      await deliver(_telemetry());

      expect(await pending, const Duration(milliseconds: 90));
      expect(controller.state.errorMessage, isNull);
    });

    test('un échec laisse un message affichable et relève l’erreur', () async {

      await expectLater(
        controller.testConnection(),
        throwsA(isA<DeviceException>()),
      );
      expect(controller.state.errorMessage, contains('connexion'));
    });
  });

  group('sans liaison MQTT', () {
    setUp(() {
      build(withDriver: false);
    });

    test('start ne fait rien et ne signale pas d’erreur', () async {

      await controller.start();

      expect(controller.state.isModuleOnline, isFalse);
      expect(controller.state.errorMessage, isNull);
      expect(controller.framesReceived, 0);
    });

    test('refreshFreshness reste à faux', () {
      controller.refreshFreshness();
      expect(controller.state.isFresh, isFalse);
    });

    test('testConnection explique qu’il n’y a rien à tester', () async {
      await expectLater(
        controller.testConnection(),
        throwsA(
          isA<DeviceException>().having(
            (DeviceException e) => e.message,
            'message',
            contains('réglages'),
          ),
        ),
      );
    });
  });

  group('état exposé', () {
    test('toString reste lisible en journal', () async {
      await controller.start();
      await deliver(_telemetry(ph: 7.24));
      expect(controller.state.toString(), contains('7.24'));
      expect(controller.state.toString(), contains('en ligne: true'));
    });

    test('copyWith efface l’erreur sur demande', () {
      const TelemetryState state = TelemetryState(errorMessage: 'panne');
      expect(state.copyWith(clearError: true).errorMessage, isNull);
      expect(state.copyWith().errorMessage, 'panne');
    });
  });
}
