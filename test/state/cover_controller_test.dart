import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/devices/pool_device_driver.dart';
import 'package:mypool/data/devices/simulation_driver.dart';
import 'package:mypool/models/cover_state.dart';
import 'package:mypool/models/pool_config.dart';
import 'package:mypool/state/cover_controller.dart';

/// Minuteur de test : les battements sont déclenchés à la main.
///
/// Sans lui, vérifier la mécanique de doigt maintenu demanderait d'attendre
/// réellement 700 ms par battement.
class FakeTimer implements Timer {
  FakeTimer(this._onTick);

  final void Function(Timer timer) _onTick;
  bool _cancelled = false;
  int _tick = 0;

  /// Nombre de battements demandés depuis la création.
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

  /// Piscine consentie, avec un volet immergé : le cas nominal.
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

  /// Déclenche un battement de republication et laisse les futures se résoudre.
  Future<void> beat() async {
    timers.last.fire();
    await pumpEventQueue();
  }

  group('règle n° 4 : sans consentement, aucune commande ne part', () {
    test('pressOpen ne touche pas le module', () async {
      config = const PoolConfig(); // consentement non donné

      expect(await controller.pressOpen(), isFalse);
      // Le compteur du pilote est le juge : pas une seule impulsion.
      expect(driver.pulseCount, 0);
      expect(controller.state.refusal, CoverRefusal.consentMissing);
      expect(controller.state.cover.motion, CoverMotion.idle);
      // Aucune republication n'a été engagée.
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

      // L'utilisateur retire son consentement dans les réglages.
      config = const PoolConfig();
      expect(await controller.pressOpen(), isFalse);
      expect(driver.pulseCount, 1);
    });

    test('sans volet motorisé, la commande est refusée', () async {
      // Une bâche à bulles ne se pilote pas.
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
        // Le contact est réellement fermé côté module.
        expect(await driver.relayState(DeviceChannel.coverOpen), isTrue);
      },
    );

    test('chaque battement renvoie une impulsion', () async {
      await controller.pressOpen();
      expect(driver.pulseCount, 1);

      // Trois battements de 700 ms : trois impulsions de plus.
      for (int i = 0; i < 3; i++) {
        advance(CoverSafety.holdRepeatInterval);
        await beat();
      }
      expect(driver.pulseCount, 4);
      expect(controller.state.cover.motion, CoverMotion.opening);
    });

    test('l’impulsion porte la temporisation matérielle', () async {
      await controller.pressOpen();
      // Le contact reste fermé tant que le délai de garde n'a pas expiré.
      advance(const Duration(milliseconds: 1700));
      expect(await driver.relayState(DeviceChannel.coverOpen), isTrue);
      // 1 800 ms après la dernière impulsion, il retombe.
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

      // Le point essentiel : le compteur d'impulsions n'a pas bougé. L'arrêt
      // n'est pas commandé, il est constaté quand le délai de garde expire.
      expect(driver.pulseCount, pulsesBeforeRelease);
      expect(controller.state.cover.motion, CoverMotion.idle);
      expect(controller.isHeld, isFalse);
      expect(timers.last.isActive, isFalse);
    });

    test('après relâchement, le contact retombe de lui-même', () async {
      await controller.pressOpen();
      await controller.release();

      // Rien n'a été envoyé, et pourtant le contact s'ouvre.
      advance(const Duration(milliseconds: 1801));
      expect(await driver.relayState(DeviceChannel.coverOpen), isFalse);
    });

    test('un battement après relâchement n’envoie rien', () async {
      await controller.pressOpen();
      final FakeTimer timer = timers.last;
      await controller.release();

      // Le minuteur est annulé : même déclenché de force, il ne fait rien.
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

        // Le module devient injoignable pendant le mouvement.
        driver.setOnline(false);
        advance(CoverSafety.holdRepeatInterval);
        await beat();

        // La republication est coupée et l'utilisateur reçoit une phrase
        // affichable. Le matériel, lui, s'arrêtera seul en moins de 2 s.
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
        // Pas de republication engagée sur un module muet.
        expect(controller.isHeld, isFalse);
      },
    );
  });

  group('estimation de position', () {
    test('9 s de doigt posé sur une course de 90 s font 10 %', () async {
      await controller.pressOpen();
      // La position ne bouge qu'au fil des battements : elle est intégrée à
      // partir du temps de doigt posé.
      for (int i = 0; i < 12; i++) {
        advance(const Duration(milliseconds: 750));
        await beat();
      }
      // 12 x 750 ms = 9 000 ms sur 90 000 ms de course = 10 %
      expect(controller.state.cover.openRatio, closeTo(0.10, 1e-9));
      expect(controller.state.cover.position, CoverPosition.partiallyOpen);
      // Sans capteur, la position reste présentée comme une estimation.
      expect(controller.state.cover.isEstimated, isTrue);
    });

    test('le relâchement fige la dernière estimation', () async {
      await controller.pressOpen();
      advance(const Duration(seconds: 9));
      await controller.release();
      // 9 s / 90 s = 10 %
      expect(controller.state.cover.openRatio, closeTo(0.10, 1e-9));

      // Le temps qui passe ensuite ne bouge plus rien.
      advance(const Duration(minutes: 5));
      expect(controller.state.cover.openRatio, closeTo(0.10, 1e-9));
    });

    test('la fermeture fait décroître l’estimation', () async {
      controller.declarePosition(open: true);
      expect(controller.state.cover.openRatio, 1.0);

      await controller.pressClose();
      advance(const Duration(seconds: 9));
      await controller.release();
      // 1,0 - 9/90 = 0,90
      expect(controller.state.cover.openRatio, closeTo(0.90, 1e-9));
    });

    test('l’estimation reste bornée entre 0 et 1', () async {
      await controller.pressOpen();
      // Bien plus long que la course complète.
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
      // C'est un humain qui affirme, pas un capteur : la mention « estimée »
      // ne disparaît pas (règle n° 6).
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
      // Recaler pendant une manœuvre donnerait une position fantaisiste.
      expect(controller.state.cover.openRatio, before);
    });
  });

  group('changement de sens', () {
    test('un ordre inverse pendant un mouvement change de sens', () async {
      await controller.pressOpen();
      advance(const Duration(seconds: 9));
      await beat();
      // 9 s / 90 s = 10 % d'ouverture faite.
      expect(controller.state.cover.openRatio, closeTo(0.10, 1e-9));
      final FakeTimer openTimer = timers.last;

      expect(await controller.pressClose(), isTrue);

      // L'ancienne republication est coupée, une nouvelle est engagée.
      expect(openTimer.isActive, isFalse);
      expect(controller.state.cover.motion, CoverMotion.closing);
      // Côté module, seul le contact de fermeture est fermé.
      expect(await driver.relayState(DeviceChannel.coverOpen), isFalse);
      expect(await driver.relayState(DeviceChannel.coverClose), isTrue);

      advance(const Duration(seconds: 9));
      await beat();
      // 10 % d'ouverture puis 10 % de fermeture : retour au point de départ.
      expect(controller.state.cover.openRatio, closeTo(0.0, 1e-9));
    });

    test(
      'deux pressions dans le même sens ne créent qu’une republication',
      () async {
        await controller.pressOpen();
        await controller.pressOpen();
        // Deux impulsions envoyées, mais un seul minuteur actif : un doigt qui
        // glisse ne doit pas doubler la cadence.
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

        // L'estimation est à 100 %, mais le contrôleur ne s'arrête pas de
        // lui-même : les fins de course sont dans le coffret, pas ici.
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
        // Le volet part de fermé : la butée d'ouverture n'est pas atteinte.
        advance(CoverSafety.holdRepeatInterval);
        await beat();
        expect(controller.state.cover.motion, CoverMotion.opening);

        // Le volet atteint la butée haute.
        sensed.calibrateCover(open: true);
        advance(CoverSafety.holdRepeatInterval);
        await beat();

        expect(controller.state.cover.motion, CoverMotion.idle);
        expect(controller.state.cover.position, CoverPosition.open);
        // Une vraie mesure : la mention « estimée » disparaît.
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
      // Un affichage ne doit jamais pouvoir faire bouger le volet.
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
      // Sans le drapeau, le message survit.
      expect(status.copyWith().errorMessage, isNotNull);
    });
  });

  group('règle n° 3 : aucune fermeture programmée', () {
    test('le contrôleur n’expose aucune commande de position ou d’horaire', () {
      // Garde-fou de source : une commande « va à 50 % » ou « ferme à 20 h »
      // ferait exécuter au matériel un mouvement sans supervision humaine.
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
      // Deux intervalles de republication doivent rester sous le délai de
      // garde, sinon deux messages perdus arrêteraient le volet à tort.
      expect(
        CoverSafety.holdRepeatInterval * 2,
        lessThan(CoverSafety.holdTimeout),
      );
      // Et le délai de garde doit rester sous la limite de la norme.
      expect(CoverSafety.holdTimeout, lessThan(const Duration(seconds: 2)));
      expect(CoverSafety.maxCoverAutoOff, const Duration(seconds: 2));
    });
  });
}
