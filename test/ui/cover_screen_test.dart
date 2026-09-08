import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/devices/pool_device_driver.dart';
import 'package:mypool/data/devices/simulation_driver.dart';
import 'package:mypool/data/readings_database.dart';
import 'package:mypool/data/settings_store.dart';
import 'package:mypool/models/pool_config.dart';
import 'package:mypool/state/providers.dart';
import 'package:mypool/ui/cover_screen.dart';
import 'package:mypool/ui/theme.dart';
import 'package:mypool/ui/widgets/hold_button.dart';
import 'package:mypool/ui/widgets/safety_consent_sheet.dart';

void main() {
  late SimulationDriver driver;
  late ProviderContainer container;

  // Une vue de téléphone plutôt que le 800 x 600 par défaut des tests : la
  // disposition de l'écran est faite pour un portrait étroit, et la tester
  // sur un paysage large ne prouverait rien.
  /// Règle la vue sur un portrait de téléphone plutôt que le 800 x 600 par
  /// défaut des tests : la disposition est faite pour un écran étroit, et la
  /// vérifier sur un paysage large ne prouverait rien.
  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  /// Écran câblé sur un pilote de simulation observable.
  Widget build({required PoolConfig config}) {
    driver = SimulationDriver();
    container = ProviderContainer(
      overrides: <Override>[
        settingsStoreProvider.overrideWithValue(
          InMemorySettingsStore(poolConfig: config),
        ),
        readingsRepositoryProvider.overrideWithValue(
          InMemoryReadingsRepository(),
        ),
        deviceDriverProvider.overrideWithValue(driver),
      ],
    );
    addTearDown(container.dispose);
    // La configuration est chargée d'avance : l'écran doit refléter l'état
    // enregistré, pas les défauts.
    container.read(poolConfigProvider.notifier).replace(config);

    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: CoverScreen()),
      ),
    );
  }

  PoolConfig consented() =>
      const PoolConfig().copyWith(safetyConsentGiven: true);

  group('règle n° 4 : sans consentement, rien ne part', () {
    testWidgets('les boutons sont inactifs et expliqués', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(config: const PoolConfig()));
      await tester.pumpAndSettle();

      expect(find.text('Commandes verrouillées'), findsOneWidget);
      expect(find.text('Avertissement à accepter'), findsNWidgets(2));

      for (final HoldButton button in tester.widgetList<HoldButton>(
        find.byType(HoldButton),
      )) {
        expect(button.enabled, isFalse);
      }
    });

    testWidgets('appuyer n’envoie aucune impulsion', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(config: const PoolConfig()));
      await tester.pumpAndSettle();

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('Ouvrir')),
      );
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      await tester.pumpAndSettle();

      // Le compteur du pilote est le juge : pas une seule impulsion.
      expect(driver.pulseCount, 0);
    });

    testWidgets('l’avertissement s’affiche et débloque les commandes', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(config: const PoolConfig()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lire l’avertissement'));
      await tester.pumpAndSettle();

      // Le texte dit quoi faire, pas seulement que c'est dangereux.
      expect(find.byType(SafetyConsentSheet), findsOneWidget);
      expect(find.textContaining('VOYEZ le bassin'), findsOneWidget);
      expect(find.textContaining('doigt reste'), findsOneWidget);
      expect(find.textContaining('estimation'), findsOneWidget);

      await tester.ensureVisible(find.text('J’ai compris'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('J’ai compris'));
      await tester.pumpAndSettle();

      expect(container.read(poolConfigProvider).safetyConsentGiven, isTrue);
      expect(find.text('Commandes verrouillées'), findsNothing);
    });

    testWidgets('refuser l’avertissement laisse les commandes verrouillées', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(config: const PoolConfig()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lire l’avertissement'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Plus tard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plus tard'));
      await tester.pumpAndSettle();

      expect(container.read(poolConfigProvider).safetyConsentGiven, isFalse);
      expect(find.text('Commandes verrouillées'), findsOneWidget);
    });
  });

  group('règle n° 1 : le mouvement suit le doigt', () {
    testWidgets('le doigt posé commande, le doigt relevé arrête', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(config: consented()));
      await tester.pumpAndSettle();

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('Ouvrir')),
      );
      await tester.pump();
      expect(driver.pulseCount, 1);
      expect(await driver.relayState(DeviceChannel.coverOpen), isTrue);

      await gesture.up();
      await tester.pumpAndSettle();

      // Aucune impulsion supplémentaire n'a été envoyée au relâchement :
      // l'arrêt vient du délai de garde matériel.
      expect(driver.pulseCount, 1);
    });

    testWidgets('la fermeture utilise l’autre canal', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(config: consented()));
      await tester.pumpAndSettle();

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('Fermer')),
      );
      await tester.pump();
      expect(await driver.relayState(DeviceChannel.coverClose), isTrue);
      expect(await driver.relayState(DeviceChannel.coverOpen), isFalse);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('quitter l’écran sous le doigt arrête le mouvement', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(config: consented()));
      await tester.pumpAndSettle();

      await tester.startGesture(tester.getCenter(find.text('Ouvrir')));
      await tester.pump();
      final int pulses = driver.pulseCount;

      // L'écran disparaît : changement d'onglet, retour, fermeture.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
        ),
      );
      await tester.pumpAndSettle();

      // Aucune commande de plus, et la répétition est coupée.
      expect(driver.pulseCount, pulses);
    });
  });

  group('règle n° 6 : la position est une estimation', () {
    testWidgets('la mention est affichée avec son origine', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(config: consented()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Position estimée'), findsOneWidget);
      expect(find.textContaining('sans capteur'), findsOneWidget);
      expect(find.textContaining('Vérifiez de vos yeux'), findsOneWidget);
    });

    testWidgets('le recalage déclaré reste une estimation', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(config: consented()));
      await tester.pumpAndSettle();

      // Le bloc de recalage est en bas de la liste : on l'amène à l'écran.
      await tester.scrollUntilVisible(
        find.text('Il est ouvert'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Il est ouvert'));
      await tester.pumpAndSettle();

      expect(find.text('VOLET OUVERT'), findsOneWidget);
      expect(find.textContaining('100'), findsWidgets);
      // C'est un humain qui a affirmé, pas un capteur.
      expect(find.textContaining('Position estimée'), findsOneWidget);
    });
  });

  group('couverture non pilotable', () {
    testWidgets('une bâche à bulles n’offre aucune commande', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        build(config: consented().copyWith(cover: CoverType.bubbleCover)),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('n’est pas un volet motorisé'),
        findsOneWidget,
      );
      for (final HoldButton button in tester.widgetList<HoldButton>(
        find.byType(HoldButton),
      )) {
        expect(button.enabled, isFalse);
      }
    });
  });

  group('panne de liaison', () {
    testWidgets('le message du module est affiché tel quel', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(config: consented()));
      await tester.pumpAndSettle();

      driver.setOnline(false);
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('Ouvrir')),
      );
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      // Une phrase en français, sans trace technique.
      expect(find.textContaining('Le module ne répond pas'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });
  });
}
