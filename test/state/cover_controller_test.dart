import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/devices/pool_device_driver.dart';
import 'package:mypool/data/devices/simulation_driver.dart';
import 'package:mypool/models/cover_state.dart';
import 'package:mypool/models/pool_config.dart';
import 'package:mypool/state/cover_controller.dart';

class FakeTimer implements Timer {
  FakeTimer(this._onTick);

  final void Function(Timer timer) _onTick;
  bool _cancelled = false;
  int _tick = 0;

  int get firedCount => _tick;

  void fire() {
    if (_cancelled) {
      return;
    }
    _tick++;
    _onTick(this);
  }

  @override
  void cancel() {
    _cancelled = true;
  }

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => _tick;
}

void main() {
  late DateTime now;
  late SimulationDriver driver;
  late PoolConfig config;
  late CoverController controller;
  late List<FakeTimer> timers;

  PoolConfig consented() =>
      const PoolConfig().copyWith(safetyConsentGiven: true);

  void build() {
    timers = <FakeTimer>[];
    controller = CoverController(
      driver: driver,
      config: () => config,
      clock: () => now,
      timerFactory: (Duration interval, void Function(Timer) onTick) {
        expect(interval, CoverSafety.holdRepeatInterval);
        final FakeTimer timer = FakeTimer(onTick);
        timers.add(timer);
        return timer;
      },
    );
  }

  setUp(() {
    now = DateTime.utc(2026, 7, 15, 10);
    driver = SimulationDriver(clock: () => now);
    config = consented();
    build();
  });

  tearDown(() {
    controller.dispose();
  });

  void advance(Duration duration) {
    now = now.add(duration);
  }

  Future<void> beat() async {
    timers.last.fire();
    await pumpEventQueue();
  }

  group('règle n° 4 : sans consentement, aucune commande ne part', () {
    test('pressOpen ne touche pas le module', () async {
      config = const PoolConfig(); 

      expect(await controller.pressOpen(), isFalse);

      expect(driver.pulseCount, 0);
      expect(controller.state.refusal, CoverRefusal.consentMissing);
      expect(controller.state.cover.motion, CoverMotion.idle);

      expect(timers, isEmpty);
      expect(controller.isHeld, isFalse);
    });

    test('pressClose non plus', () async {
      config = const PoolConfig();
      expect(await controller.pressClose(), isFalse);
      expect(driver.pulseCount, 0);
    });

    test('le consentement retiré en cours de session bloque le battement '
        'suivant', () async {
      expect(await controller.pressOpen(), isTrue);
      expect(driver.pulseCount, 1);

      config = const PoolConfig();
      expect(await controller.pressOpen(), isFalse);
      expect(driver.pulseCount, 1);
    });

    test('sans volet motorisé, la commande est refusée', () async {

      config = consented().copyWith(cover: CoverType.bubbleCover);
      expect(await controller.pressOpen(), isFalse);
      expect(controller.state.refusal, CoverRefusal.noMotorisedCover);
      expect(driver.pulseCount, 0);
    });
  });

  group('règle n° 1 : le mouvement suit le doigt', () {
    test(
      'une pression envoie une impulsion et engage la republication',
      () async {
        expect(await controller.pressOpen(), isTrue);

        expect(driver.pulseCount, 1);
        expect(controller.state.cover.motion, CoverMotion.opening);
        expect(controller.isHeld, isTrue);
        expect(timers.length, 1);
        expect(timers.first.isActive, isTrue);

        expect(await driver.relayState(DeviceChannel.coverOpen), isTrue);
      },
    );

    test('chaque battement renvoie une impulsion', () async {
      await controller.pressOpen();
      expect(driver.pulseCount, 1);

      for (int i = 0; i < 3; i++) {
        advance(CoverSafety.holdRepeatInterval);
        await beat();
      }
      expect(driver.pulseCount, 4);
      expect(controller.state.cover.motion, CoverMotion.opening);
    });

    test('l’impulsion porte la temporisation matérielle', () async {
      await controller.pressOpen();

      advance(const Duration(milliseconds: 1700));
      expect(await driver.relayState(DeviceChannel.coverOpen), isTrue);

      advance(const Duration(milliseconds: 200));
      expect(await driver.relayState(DeviceChannel.coverOpen), isFalse);
    });
  });

  group('règle n° 2 : le relâchement n’envoie aucun ordre', () {
    test('release coupe la republication sans rien envoyer', () async {
      await controller.pressOpen();
      advance(CoverSafety.holdRepeatInterval);
      await beat();
      final int pulsesBeforeRelease = driver.pulseCount;
      expect(pulsesBeforeRelease, 2);

      await controller.release();

      expect(driver.pulseCount, pulsesBeforeRelease);
      expect(controller.state.cover.motion, CoverMotion.idle);
      expect(controller.isHeld, isFalse);
      expect(timers.last.isActive, isFalse);
    });

    test('après relâchement, le contact retombe de lui-même', () async {
      await controller.pressOpen();
      await controller.release();

      advance(const Duration(milliseconds: 1801));
      expect(await driver.relayState(DeviceChannel.coverOpen), isFalse);
    });

    test('un battement après relâchement n’envoie rien', () async {
      await controller.pressOpen();
      final FakeTimer timer = timers.last;
      await controller.release();

      timer.fire();
      await pumpEventQueue();
      expect(driver.pulseCount, 1);
      expect(controller.state.cover.motion, CoverMotion.idle);
    });

    test('release est sans effet quand rien ne bouge', () async {
      await controller.release();
      expect(driver.pulseCount, 0);
      expect(controller.state.cover.motion, CoverMotion.idle);
    });

    test(
      'une perte de liaison en pleine manœuvre arrête la republication',
      () async {
        await controller.pressOpen();
        expect(driver.pulseCount, 1);

        driver.setOnline(false);
        advance(CoverSafety.holdRepeatInterval);
        await beat();

        expect(controller.state.cover.motion, CoverMotion.idle);
        expect(controller.state.refusal, CoverRefusal.deviceError);
        expect(controller.state.errorMessage, contains('module'));
        expect(controller.isHeld, isFalse);
      },
    );

    test(
      'une première pression sur un module injoignable échoue proprement',
      () async {
        driver.setOnline(false);
        expect(await controller.pressOpen(), isFalse);
        expect(controller.state.cover.motion, CoverMotion.idle);
        expect(controller.state.errorMessage, isNotNull);

        expect(controller.isHeld, isFalse);
      },
    );
  });

  group('estimation de position', () {
    test('9 s de doigt posé sur une course de 90 s font 10 %', () async {
      await controller.pressOpen();

      for (int i = 0; i < 12; i++) {
        advance(const Duration(milliseconds: 750));
        await beat();
      }

      expect(controller.state.cover.openRatio, closeTo(0.10, 1e-9));
      expect(controller.state.cover.position, CoverPosition.partiallyOpen);

      expect(controller.state.cover.isEstimated, isTrue);
    });

    test('le relâchement fige la dernière estimation', () async {
      await controller.pressOpen();
      advance(const Duration(seconds: 9));
      await controller.release();

      expect(controller.state.cover.openRatio, closeTo(0.10, 1e-9));

      advance(const Duration(minutes: 5));
      expect(controller.state.cover.openRatio, closeTo(0.10, 1e-9));
    });

    test('la fermeture fait décroître l’estimation', () async {
      controller.declarePosition(open: true);
      expect(controller.state.cover.openRatio, 1.0);

      await controller.pressClose();
      advance(const Duration(seconds: 9));
      await controller.release();

      expect(controller.state.cover.openRatio, closeTo(0.90, 1e-9));
    });

    test('l’estimation reste bornée entre 0 et 1', () async {
      await controller.pressOpen();

      advance(const Duration(minutes: 5));
      await controller.release();
      expect(controller.state.cover.openRatio, 1.0);
      expect(controller.state.cover.position, CoverPosition.open);
    });

    test(
      'une course déclarée nulle ne fait pas diverger l’estimation',
      () async {
        config = consented().copyWith(coverTravelSeconds: 0.0);
        await controller.pressOpen();
        advance(const Duration(seconds: 9));
        await controller.release();
        expect(controller.state.cover.openRatio, 0.0);
      },
    );

    test('declarePosition reste une estimation, pas une mesure', () async {

      controller.declarePosition(open: false);
      expect(controller.state.cover.position, CoverPosition.closed);
      expect(controller.state.cover.isEstimated, isTrue);
    });

    test('declarePosition est refusée pendant un mouvement', () async {
      await controller.pressOpen();
      advance(const Duration(seconds: 9));
      await beat();
      final double before = controller.state.cover.openRatio;
      controller.declarePosition(open: true);

      expect(controller.state.cover.openRatio, before);
    });
  });

  group('changement de sens', () {
    test('un ordre inverse pendant un mouvement change de sens', () async {
      await controller.pressOpen();
      advance(const Duration(seconds: 9));
      await beat();

      expect(controller.state.cover.openRatio, closeTo(0.10, 1e-9));
      final FakeTimer openTimer = timers.last;

      expect(await controller.pressClose(), isTrue);

      expect(openTimer.isActive, isFalse);
      expect(controller.state.cover.motion, CoverMotion.closing);

      expect(await driver.relayState(DeviceChannel.coverOpen), isFalse);
      expect(await driver.relayState(DeviceChannel.coverClose), isTrue);

      advance(const Duration(seconds: 9));
      await beat();

      expect(controller.state.cover.openRatio, closeTo(0.0, 1e-9));
    });

    test(
      'deux pressions dans le même sens ne créent qu’une republication',
      () async {
        await controller.pressOpen();
        await controller.pressOpen();

        expect(driver.pulseCount, 2);
        expect(timers.length, 1);
        expect(timers.first.isActive, isTrue);
      },
    );
  });

  group('règle n° 6 : la fin de course, quand elle existe, fait autorité', () {
    test(
      'sans capteur, le mouvement continue et la position reste estimée',
      () async {
        await controller.pressOpen();
        advance(const Duration(minutes: 5));
        await beat();

        expect(controller.state.cover.openRatio, 1.0);
        expect(controller.state.cover.isEstimated, isTrue);
        expect(controller.state.cover.motion, CoverMotion.opening);
      },
    );

    test(
      'avec capteur, la butée arrête le mouvement et lève l’estimation',
      () async {
        final SimulationDriver sensed = SimulationDriver(
          clock: () => now,
          hasLimitSwitches: true,
        );
        driver = sensed;
        build();

        await controller.pressOpen();

        advance(CoverSafety.holdRepeatInterval);
        await beat();
        expect(controller.state.cover.motion, CoverMotion.opening);

        sensed.calibrateCover(open: true);
        advance(CoverSafety.holdRepeatInterval);
        await beat();

        expect(controller.state.cover.motion, CoverMotion.idle);
        expect(controller.state.cover.position, CoverPosition.open);

        expect(controller.state.cover.isEstimated, isFalse);
        expect(controller.isHeld, isFalse);
      },
    );
  });

  group('lecture de la pompe', () {
    test('refreshPump lit l’état et la puissance', () async {
      await driver.setRelay(DeviceChannel.pump, on: true);
      await controller.refreshPump();

      expect(controller.state.cover.pump, PumpState.on);
      expect(controller.state.cover.pumpPowerW, 450.0);

      await driver.setRelay(DeviceChannel.pump, on: false);
      await controller.refreshPump();
      expect(controller.state.cover.pump, PumpState.off);
      expect(controller.state.cover.pumpPowerW, 0.0);
    });

    test('un module muet rend l’état de pompe inconnu', () async {
      driver.setOnline(false);
      await controller.refreshPump();
      expect(controller.state.cover.pump, PumpState.unknown);
      expect(controller.state.errorMessage, isNotNull);
    });

    test('un rafraîchissement ne déclenche aucun mouvement', () async {
      await controller.refreshPump();

      expect(driver.pulseCount, 0);
      expect(controller.state.cover.motion, CoverMotion.idle);
    });
  });

  group('état exposé', () {
    test('isMoving suit le mouvement', () async {
      expect(controller.state.isMoving, isFalse);
      await controller.pressOpen();
      expect(controller.state.isMoving, isTrue);
      await controller.release();
      expect(controller.state.isMoving, isFalse);
    });

    test('toString reste lisible en journal', () async {
      config = const PoolConfig();
      await controller.pressOpen();
      final String text = controller.state.toString();
      expect(text, contains('idle'));
      expect(text, contains('consentMissing'));
    });

    test('copyWith efface l’erreur sur demande', () {
      const CoverStatus status = CoverStatus(
        refusal: CoverRefusal.deviceError,
        errorMessage: 'Le module ne répond pas.',
      );
      expect(status.copyWith(clearError: true).errorMessage, isNull);

      expect(status.copyWith().errorMessage, isNotNull);
    });
  });

  group('règle n° 3 : aucune fermeture programmée', () {
    test('le contrôleur n’expose aucune commande de position ou d’horaire', () {

      final String source = File('lib/state/cover_controller.dart')
          .readAsStringSync();
      for (final String forbidden in <String>[
        'moveTo',
        'goTo',
        'setPosition',
        'targetRatio',
        'scheduleClose',
        'autoClose',
        'Timer(',
        'Future.delayed',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: 'cover_controller.dart contient « $forbidden »',
        );
      }
    });

    test('l’interface du pilote n’accepte aucune position cible', () {
      final String source = File('lib/data/devices/pool_device_driver.dart')
          .readAsStringSync();
      for (final String forbidden in <String>[
        'moveTo',
        'setCoverPosition',
        'targetPosition',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('le délai de garde matériel tient sous les 2 s de la règle n° 2', () {

      expect(
        CoverSafety.holdRepeatInterval * 2,
        lessThan(CoverSafety.holdTimeout),
      );

      expect(CoverSafety.holdTimeout, lessThan(const Duration(seconds: 2)));
      expect(CoverSafety.maxCoverAutoOff, const Duration(seconds: 2));
    });
  });
}
