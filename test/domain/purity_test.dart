import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Garde-fou d'architecture.
///
/// La couverture à 100 % du moteur métier repose sur une seule chose : aucun
/// fichier de `lib/domain/` ne dépend de Flutter, de la base de données, du
/// réseau ou de l'horloge. Ce test echoue des qu'un import interdit apparait,
/// avant que la dette ne devienne invisible.
void main() {
  /// Paquets et bibliotheques que `lib/domain/` ne doit jamais importer.
  const List<String> forbiddenImports = <String>[
    'package:flutter/',
    'package:flutter_riverpod/',
    'package:sqflite/',
    'package:http/',
    'package:shared_preferences/',
    'package:path/',
    'dart:io',
    'dart:ui',
  ];

  /// Appels qui rendraient un calcul non reproductible.
  const List<String> forbiddenCalls = <String>[
    'DateTime.now(',
    'Timer(',
    'Future.delayed(',
  ];

  test('lib/domain/ ne dépend ni de Flutter, ni du disque, ni du réseau', () {
    final List<File> files = Directory('lib/domain')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.endsWith('.dart'))
        .toList(growable: false);

    // La phase 1 livre trois moteurs : chimie, équilibre, filtration.
    expect(files.length, greaterThanOrEqualTo(3));

    for (final File file in files) {
      final String source = file.readAsStringSync();
      for (final String forbidden in forbiddenImports) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: '${file.path} importe $forbidden',
        );
      }
      for (final String forbidden in forbiddenCalls) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason:
              '${file.path} appelle $forbidden : tout doit entrer par '
              'parametre pour que le calcul soit reproductible',
        );
      }
    }
  });

  test('le sens des dépendances est respecté', () {
    // « ui → state → domain/data → models. Jamais l'inverse. » Une couche qui
    // remonte est le premier pas vers un moteur de dosage qu'on ne peut plus
    // tester sans écran.
    const Map<String, List<String>> forbidden = <String, List<String>>{
      // Les modèles sont au fond : ils ne connaissent personne.
      'lib/models': <String>['/domain/', '/data/', '/state/', '/ui/'],
      // Le domaine calcule ; il ne sait ni où sont les données ni qui les
      // affiche.
      'lib/domain': <String>['/data/', '/state/', '/ui/'],
      // La persistance et les pilotes ne remontent pas vers les contrôleurs.
      'lib/data': <String>['/state/', '/ui/'],
      // Les contrôleurs orchestrent ; ils ne connaissent aucun écran.
      'lib/state': <String>['/ui/'],
    };

    forbidden.forEach((String layer, List<String> banned) {
      final Directory directory = Directory(layer);
      if (!directory.existsSync()) {
        return;
      }
      for (final File file
          in directory
              .listSync(recursive: true)
              .whereType<File>()
              .where((File f) => f.path.endsWith('.dart'))) {
        final Iterable<String> imports = file.readAsLinesSync().where(
          (String line) => line.startsWith('import '),
        );
        for (final String line in imports) {
          for (final String target in banned) {
            expect(
              line,
              isNot(contains(target)),
              reason: '${file.path} importe $target',
            );
          }
        }
      }
    });
  });

  test('lib/models/ ne dépend pas de Flutter non plus', () {
    // Les modèles traversent toutes les couches : les garder sans Flutter
    // permet de les tester, de les serialiser et de les reutiliser tels quels.
    final List<File> files = Directory('lib/models')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.endsWith('.dart'))
        .toList(growable: false);

    expect(files.length, greaterThanOrEqualTo(6));

    for (final File file in files) {
      final String source = file.readAsStringSync();
      for (final String forbidden in <String>[
        'package:flutter/',
        'package:sqflite/',
        'package:http/',
        'dart:io',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: '${file.path} importe $forbidden',
        );
      }
    }
  });
}
