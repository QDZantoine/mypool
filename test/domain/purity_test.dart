import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {

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

    const Map<String, List<String>> forbidden = <String, List<String>>{

      'lib/models': <String>['/domain/', '/data/', '/state/', '/ui/'],

      'lib/domain': <String>['/data/', '/state/', '/ui/'],

      'lib/data': <String>['/state/', '/ui/'],

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
