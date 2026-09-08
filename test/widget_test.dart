import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/readings_database.dart';
import 'package:mypool/data/settings_store.dart';
import 'package:mypool/state/providers.dart';
import 'package:mypool/ui/app.dart';
import 'package:mypool/ui/home_screen.dart';
import 'package:mypool/services/weather-service.dart';
import 'package:mypool/state/providers.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Démarrage de l'application, de bout en bout.
///
/// Le test qui compte le plus dans ce fichier est le premier : l'application
/// doit s'ouvrir et être utilisable AVANT que quoi que ce soit ait été lu sur
/// le disque. C'est la règle du projet, et elle se vérifie ici en n'attendant
/// délibérément aucun chargement.
void main() {
  Widget app({
    InMemorySettingsStore? settings,
    InMemoryReadingsRepository? readings,
  }) {
    return ProviderScope(
      overrides: <Override>[
        settingsStoreProvider.overrideWithValue(
          settings ?? InMemorySettingsStore(),
        ),
        readingsRepositoryProvider.overrideWithValue(
          readings ?? InMemoryReadingsRepository(),
        ),
      ],
      child: const AquaControlApp(),
    );
  }

  testWidgets('l’application s’ouvre sur l’accueil', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app());
    // Une seule image, aucun chargement attendu.
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    // Le nom du bassin par défaut est affiché dans la barre.
    expect(find.text('Ma piscine'), findsOneWidget);
    // Sans mesure, le verdict le dit et explique quoi faire.
    expect(find.text('Pas encore de mesure'), findsOneWidget);
    expect(find.textContaining('Testez l’eau'), findsOneWidget);
  });

  testWidgets('les quatre destinations sont accessibles', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    for (final String label in <String>[
      'Volet',
      'Filtration',
      'Réglages',
      'Eau',
    ]) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    // Retour sur l'accueil sans erreur.
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la navigation ne dépasse pas deux niveaux', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Niveau 1 : les destinations. Niveau 2 : la saisie, ouverte par-dessus
    // depuis l'action du panneau d'accueil.
    await tester.tap(find.text('Saisir une mesure'));
    await tester.pumpAndSettle();
    expect(find.text('Compléter les mesures'), findsOneWidget);

    // Un seul retour ramène à l'accueil.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
