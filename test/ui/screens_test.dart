import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/readings_database.dart';
import 'package:mypool/data/settings_store.dart';
import 'package:mypool/models/chemical_product.dart';
import 'package:mypool/models/pool_config.dart';
import 'package:mypool/models/water_reading.dart';
import 'package:mypool/state/providers.dart';
import 'package:mypool/ui/actions_screen.dart';
import 'package:mypool/ui/filtration_screen.dart';
import 'package:mypool/ui/history_screen.dart';
import 'package:mypool/ui/home_screen.dart';
import 'package:mypool/ui/reading_entry_screen.dart';
import 'package:mypool/ui/settings_screen.dart';
import 'package:mypool/ui/theme.dart';
import 'package:mypool/ui/widgets/day_timeline.dart';
import 'package:mypool/ui/widgets/history_chart.dart';

final DateTime _start = DateTime.utc(2026, 7, 15, 10);

void main() {
  late InMemoryReadingsRepository readings;
  late ProviderContainer container;

  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Widget build(Widget screen, {PoolConfig? config}) {
    readings = InMemoryReadingsRepository();
    container = ProviderContainer(
      overrides: <Override>[
        settingsStoreProvider.overrideWithValue(
          InMemorySettingsStore(poolConfig: config),
        ),
        readingsRepositoryProvider.overrideWithValue(readings),
      ],
    );
    addTearDown(container.dispose);
    if (config != null) {
      container.read(poolConfigProvider.notifier).replace(config);
    }
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: screen),
      ),
    );
  }

  Future<void> record(WaterReading reading) async {
    await container.read(readingsProvider.notifier).record(reading);
  }

  /// Amène un élément à l'écran avant de l'affirmer.
  ///
  /// Un `ListView` ne construit PAS ce qui est hors de la fenêtre : sur un
  /// portrait de téléphone, la moitié de chaque écran est en dessous. Faire
  /// défiler est donc ce que fait aussi l'utilisateur.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      300,
      // Le défilement VERTICAL de l'écran, explicitement : un `TextField` et
      // une rangée de puces portent chacun leur propre Scrollable
      // horizontal, qu'un `first` ou un `last` attraperait au hasard.
      scrollable: find.byWidgetPredicate(
        (Widget widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('accueil', () {
    testWidgets('sans mesure, il invite à mesurer', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Pas encore de mesure'), findsOneWidget);
      // Un écran vide est une invitation à agir : l'action est dans le
      // panneau, pas cachée dans un en-tête de section.
      expect(find.text('Saisir une mesure'), findsOneWidget);
      // Les échelles vides ne sont pas affichées : deux nuanciers gris
      // n'apprennent rien et prennent la place de l'invitation.
      expect(find.text('SUIVI EN CONTINU'), findsNothing);
      expect(
        find.textContaining('ne se lisent qu’à la bandelette'),
        findsOneWidget,
      );
    });

    testWidgets('une eau parfaite annonce qu’il n’y a rien à faire', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const HomeScreen()));
      await tester.pumpAndSettle();

      await record(
        WaterReading(
          takenAt: _start,
          ph: 7.2,
          freeChlorine: 2.0,
          tac: 100.0,
          th: 250.0,
          stabilizer: 30.0,
          temperature: 26.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rien à verser'), findsOneWidget);
      // La valeur et son unité forment un seul bloc de texte enrichi, pour
      // que l'unité reste plus petite que le chiffre.
      expect(find.textContaining('7,2'), findsWidgets);
      expect(find.textContaining('26,0'), findsWidgets);
    });

    testWidgets('la première action est détaillée, avec sa dose', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const HomeScreen()));
      await tester.pumpAndSettle();

      await record(WaterReading(takenAt: _start, ph: 7.8, tac: 100.0));
      await tester.pumpAndSettle();

      // 0,60 x 40 m3 x 60 g = 1 440 g, mis en forme par le métier.
      // Le verdict de tête annonce l'action, et la carte la détaille.
      expect(find.text('Baisser le pH'), findsNWidgets(2));
      expect(find.text('1,44 kg'), findsOneWidget);
      expect(find.textContaining('1,44 kg de pH moins'), findsOneWidget);
      // Fractionnée en deux apports, avec son avertissement.
      expect(find.textContaining('2 apports de 720 g'), findsOneWidget);
      expect(find.textContaining('fractionner'), findsOneWidget);
    });

    testWidgets('l’ordre métier est annoncé quand il y a plusieurs actions', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const HomeScreen()));
      await tester.pumpAndSettle();

      await record(WaterReading(takenAt: _start, ph: 7.9, tac: 60.0));
      await tester.pumpAndSettle();

      expect(find.text('À FAIRE, DANS L’ORDRE'), findsOneWidget);
      // Le TAC passe devant le pH : verdict de tête et carte détaillée.
      expect(find.text('Remonter le TAC'), findsNWidgets(2));
      expect(find.text('Baisser le pH'), findsNothing);
    });

    testWidgets('l’équilibre de l’eau est affiché avec son explication', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const HomeScreen()));
      await tester.pumpAndSettle();

      await record(
        WaterReading(
          takenAt: _start,
          ph: 7.4,
          tac: 100.0,
          th: 250.0,
          temperature: 26.0,
        ),
      );
      await tester.pumpAndSettle();

      // LSI = -0,06, avec le signe moins typographique.
      await scrollTo(tester, find.text('INDICE DE LANGELIER'));
      expect(find.text('−0,06'), findsOneWidget);
      expect(find.textContaining('L’eau est équilibrée'), findsOneWidget);
    });
  });

  group('liste des actions', () {
    testWidgets('elle numérote et explique pourquoi l’ordre compte', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const ActionsScreen()));
      await tester.pumpAndSettle();

      await record(WaterReading(takenAt: _start, ph: 7.9, tac: 60.0));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(
        find.textContaining('Le TAC tient le pH en place'),
        findsOneWidget,
      );
    });

    testWidgets('sans action, elle le dit', (WidgetTester tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const ActionsScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Rien à corriger'), findsOneWidget);
    });
  });

  group('saisie', () {
    /// Trouve le champ d'un paramètre par son libellé en capitales.
    Finder fieldOf(WaterParameter parameter) => find.ancestor(
      of: find.text(parameter.label.toUpperCase()),
      matching: find.byType(Column),
    );

    testWidgets('l’écran ne propose que ce qu’aucune sonde ne mesure', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const ReadingEntryScreen()));
      await tester.pumpAndSettle();

      // L'intitulé de l'écran dit d'où viennent ces valeurs.
      expect(
        find.textContaining('ne se lisent qu’à la bandelette'),
        findsOneWidget,
      );
      // Les valeurs qui ne se lisent qu'à la main. Le stabilisant est plus bas
      // dans la liste : la fenêtre n'en montre qu'une partie.
      expect(find.text('CHLORE LIBRE'), findsOneWidget);
      expect(find.text('TAC'), findsOneWidget);
      expect(find.text('TH'), findsOneWidget);
      await scrollTo(tester, find.text('STABILISANT'));
      expect(find.text('STABILISANT'), findsOneWidget);
    });

    testWidgets('un champ vide n’est pas un zéro', (WidgetTester tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const ReadingEntryScreen()));
      await tester.pumpAndSettle();

      // Seul le TAC est saisi.
      await scrollTo(tester, find.text('TAC'));
      await tester.enterText(
        find
            .descendant(
              of: fieldOf(WaterParameter.tac),
              matching: find.byType(TextField),
            )
            .first,
        '105',
      );
      await scrollTo(tester, find.text('Enregistrer'));
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      final WaterReading? saved = container.read(readingsProvider).latest;
      expect(saved?.tac, 105.0);
      // Tous les autres restent absents.
      expect(saved?.th, isNull);
      expect(saved?.freeChlorine, isNull);
    });

    testWidgets('la virgule décimale est acceptée', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const ReadingEntryScreen()));
      await tester.pumpAndSettle();

      // C'est ce que le clavier français propose : refuser « 1,8 » serait
      // absurde.
      await tester.enterText(find.byType(TextField).first, '1,8');
      await scrollTo(tester, find.text('Enregistrer'));
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(container.read(readingsProvider).latest?.freeChlorine, 1.8);
    });

    testWidgets('une saisie entièrement vide est refusée', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const ReadingEntryScreen()));
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('Enregistrer'));
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(find.textContaining('au moins une valeur'), findsOneWidget);
      expect(container.read(readingsProvider).isEmpty, isTrue);
    });

    testWidgets('sans sonde, le pH et la température sont proposés en repli', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const ReadingEntryScreen()));
      await tester.pumpAndSettle();

      // Aucune sonde connectée : sans ces deux valeurs, les doses seraient
      // calculées à l'aveugle.
      await scrollTo(tester, find.text('FAUTE DE SONDE'));
      expect(find.text('PH'), findsOneWidget);
      expect(find.text('TEMPÉRATURE'), findsOneWidget);
    });

    testWidgets('les champs proposés dépendent du traitement', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      // Oxygène actif : aucun champ de chlore. Demander une valeur qui n'a
      // pas de sens sur l'installation ferait douter de tout le reste.
      await tester.pumpWidget(
        build(
          const ReadingEntryScreen(),
          config: const PoolConfig().copyWith(
            treatment: TreatmentType.activeOxygen,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CHLORE LIBRE'), findsNothing);
      expect(find.text('STABILISANT'), findsNothing);
      expect(find.text('SEL'), findsNothing);
      expect(find.text('TAC'), findsOneWidget);
    });

    testWidgets('un bassin au sel propose le champ sel', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(
        build(
          const ReadingEntryScreen(),
          config: const PoolConfig().copyWith(treatment: TreatmentType.salt),
        ),
      );
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('SEL'));
      expect(find.text('SEL'), findsOneWidget);
    });
  });

  group('filtration', () {
    testWidgets('sans température, elle explique ce qui manque', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const FiltrationScreen()));
      await tester.pumpAndSettle();

      // Un état vide écrit, jamais un tiret rendu en grande taille : à 76 px
      // un « — » devient un trait plein qu'on prend pour une barre en panne.
      expect(find.text('Température inconnue'), findsOneWidget);
      expect(find.text('—'), findsNothing);
      expect(find.textContaining('suit la température'), findsOneWidget);
      // La rotation reste affichée : elle ne dépend pas de la température.
      expect(find.text('5 h 20'), findsOneWidget);
    });

    testWidgets('à 26 °C, elle annonce 13 h et trois créneaux', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const FiltrationScreen()));
      await tester.pumpAndSettle();

      await record(WaterReading(takenAt: _start, temperature: 26.0));
      await tester.pumpAndSettle();

      expect(find.textContaining('13 h'), findsWidgets);
      // La journée est dessinée avant d'être listée : une liste d'horaires
      // demande de reconstruire mentalement la journée.
      expect(find.text('LA JOURNÉE'), findsOneWidget);
      expect(find.byType(DayTimeline), findsOneWidget);
      expect(find.text('CRÉNEAUX'), findsOneWidget);
      // 390 min centrés sur 14:00 -> 10:45 à 17:15
      expect(find.text('10:45 – 17:15'), findsOneWidget);
      expect(find.text('6 h 30'), findsOneWidget);
    });

    testWidgets('en MQTT, la limite du planning est signalée', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(
        build(
          const FiltrationScreen(),
          config: const PoolConfig().copyWith(driver: DriverKind.mqtt),
        ),
      );
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('Planning non mémorisé'));
      expect(find.textContaining('téléphone est éteint'), findsOneWidget);
    });
  });

  group('historique', () {
    testWidgets('sans mesure, la courbe le dit', (WidgetTester tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const HistoryScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Aucune mesure de pH'), findsOneWidget);
    });

    testWidgets('une seule mesure ne trace pas de courbe', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const HistoryScreen()));
      await tester.pumpAndSettle();

      await record(WaterReading(takenAt: _start, ph: 7.2));
      await tester.pumpAndSettle();

      expect(find.textContaining('il en faut deux'), findsOneWidget);
    });

    testWidgets('deux mesures tracent la courbe', (WidgetTester tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const HistoryScreen()));
      await tester.pumpAndSettle();

      await record(WaterReading(takenAt: _start, ph: 7.2));
      await record(
        WaterReading(takenAt: _start.add(const Duration(days: 1)), ph: 7.6),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HistoryChart), findsOneWidget);
      expect(find.text('2 mesures'), findsOneWidget);
      // Les deux dates aux extrémités de l'axe.
      expect(find.text('15/07'), findsOneWidget);
      expect(find.text('16/07'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('on peut changer de paramètre', (WidgetTester tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const HistoryScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('TAC').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Aucune mesure de TAC'), findsOneWidget);
    });

    testWidgets('une mesure peut être supprimée', (WidgetTester tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const HistoryScreen()));
      await tester.pumpAndSettle();

      await record(WaterReading(takenAt: _start, ph: 7.2));
      await tester.pumpAndSettle();
      expect(find.text('1 mesure'), findsOneWidget);

      await scrollTo(tester, find.byIcon(Icons.delete_outline));
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(await readings.count(), 0);
    });
  });

  group('réglages', () {
    testWidgets('le volume est modifiable et enregistré', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const SettingsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Volume'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '62,5');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();

      expect(container.read(poolConfigProvider).volumeM3, 62.5);
    });

    testWidgets('l’effet du volume sur les doses est expliqué', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const SettingsScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('multiplie toutes les doses'), findsOneWidget);
    });

    testWidgets('la concentration d’un produit est modifiable', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const SettingsScreen()));
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('Chlore lent (galets)'));
      await tester.tap(find.text('Chlore lent (galets)'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '56');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();

      expect(
        container
            .read(poolConfigProvider)
            .inventory
            .forRole(ChemicalRole.chlorineSlow)
            .activePercent,
        56.0,
      );
    });

    testWidgets('réactiver le consentement passe par l’avertissement', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(build(const SettingsScreen()));
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('Avertissement du volet accepté'));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Un interrupteur qu'on rebascule sans rien lire viderait la règle n° 4
      // de son sens.
      expect(find.text('J’ai compris'), findsOneWidget);
    });

    testWidgets('chaque choix d’enum a un libellé en français', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(
        build(
          const SettingsScreen(),
          config: const PoolConfig().copyWith(driver: DriverKind.mqtt),
        ),
      );
      await tester.pumpAndSettle();

      // Ouvrir chaque liste de choix affiche toutes ses valeurs d'un coup :
      // aucun libellé ne doit manquer, ni tomber sur un nom technique.
      const Map<String, List<String>> expected = <String, List<String>>{
        'Traitement': <String>[
          'Chlore stabilisé (galets)',
          'Chlore non stabilisé',
          'Électrolyse au sel',
          'Brome',
          'Oxygène actif',
        ],
        'Filtre': <String>[
          'Sable',
          'Verre filtrant',
          'Cartouche',
          'Diatomée',
          'Zéolite',
        ],
        'Couverture': <String>[
          'Volet immergé',
          'Volet hors d’eau',
          'Couverture à barres',
          'Bâche à bulles',
          'Aucune',
        ],
        'Type de liaison': <String>[
          'Simulation (sans matériel)',
          'Module local — à venir',
          'Home Assistant — à venir',
          'Carte ESP32 en MQTT',
        ],
      };

      for (final String field in expected.keys) {
        await scrollTo(tester, find.text(field));
        await tester.tap(find.text(field));
        await tester.pumpAndSettle();
        for (final String label in expected[field]!) {
          expect(find.text(label), findsWidgets, reason: '$field : $label');
        }
        // On referme par la barrière, sans changer de valeur.
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('le broker public est signalé comme tel', (
      WidgetTester tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(
        build(
          const SettingsScreen(),
          config: const PoolConfig().copyWith(driver: DriverKind.mqtt),
        ),
      );
      await tester.pumpAndSettle();

      await scrollTo(tester, find.textContaining('Ce broker est public'));
      expect(find.textContaining('jamais à un vrai volet'), findsOneWidget);
    });
  });
}
