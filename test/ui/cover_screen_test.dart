import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/core/connection_notifier.dart';
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

  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

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

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
        ),
      );
      await tester.pumpAndSettle();

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

      expect(find.textContaining('Le module ne répond pas'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('affiche le message de connexion internet si le réseau est KO', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(config: consented()));
      await tester.pumpAndSettle();

      container
          .read(connectionNotifierProvider.notifier)
          .updateMqttStatus(isOnline: false, isMqttReady: true);
      await tester.pumpAndSettle();

      expect(find.text('Commander'), findsNothing);
      expect(find.byType(HoldButton), findsNothing);
      expect(
        find.textContaining('vérifier votre connexion internet'),
        findsOneWidget,
      );
    });

    testWidgets('affiche les commandes si la connexion internet est OK', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(config: consented()));
      await tester.pumpAndSettle();

      container
          .read(connectionNotifierProvider.notifier)
          .updateMqttStatus(isOnline: true, isMqttReady: false);
      await tester.pumpAndSettle();

      expect(find.text('COMMANDER'), findsOneWidget);
      expect(find.byType(HoldButton), findsNWidgets(2));
    });

    testWidgets('lors du retour du réseau, le message disparait automatiquement sans toucher aux boutons', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(config: consented()));
      await tester.pumpAndSettle();

      container
          .read(connectionNotifierProvider.notifier)
          .updateMqttStatus(isOnline: false, isMqttReady: false);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Problème de connexion'),
        findsOneWidget,
      );

      container
          .read(connectionNotifierProvider.notifier)
          .updateMqttStatus(isOnline: true, isMqttReady: true);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Problème de connexion'),
        findsNothing,
      );
      expect(find.text('COMMANDER'), findsOneWidget);
      expect(find.byType(HoldButton), findsNWidgets(2));
    });
  });
}
