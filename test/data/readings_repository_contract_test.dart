import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/readings_database.dart';
import 'package:mypool/models/water_reading.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final DateTime _start = DateTime.utc(2026, 7, 15, 10);

/// Valeurs littérales : comparer le résultat de `7.0 + i * 0.1` à un littéral
/// revient à comparer deux arrondis flottants, ce qui n'est pas le sujet ici.
const List<double> _phs = <double>[7.0, 7.1, 7.2, 7.3, 7.4];

WaterReading _reading({
  Duration offset = Duration.zero,
  double? ph,
  MeasurementSource source = MeasurementSource.manual,
}) {
  return WaterReading(takenAt: _start.add(offset), ph: ph, source: source);
}

/// Contrat commun aux deux implémentations de [ReadingsRepository].
///
/// Il existe pour une raison précise : les tests des contrôleurs utiliseront
/// le dépôt EN MÉMOIRE, plus rapide et sans fichier. Sans cette suite
/// partagée, rien ne garantirait qu'il se comporte comme SQLite, et un test de
/// contrôleur pourrait passer au vert sur un comportement que la vraie base ne
/// reproduit pas.
void runContract(String name, ReadingsRepository Function() create) {
  group('contrat — $name', () {
    late ReadingsRepository repository;

    setUp(() {
      repository = create();
    });

    tearDown(() async {
      await repository.close();
    });

    test('un dépôt vide n’a rien à rendre', () async {
      expect(await repository.count(), 0);
      expect(await repository.recent(), isEmpty);
      expect(await repository.latest(), isNull);
      expect(await repository.between(from: _start, to: _start), isEmpty);
    });

    test('insert rend une clé strictement positive et distincte', () async {
      final StoredReading a = await repository.insert(_reading(ph: 7.2));
      final StoredReading b = await repository.insert(_reading(ph: 7.3));
      expect(a.id, greaterThan(0));
      expect(b.id, greaterThan(0));
      expect(a.id, isNot(b.id));
      expect(await repository.count(), 2);
    });

    test('recent trie du plus récent au plus ancien', () async {
      await repository.insert(
        _reading(offset: const Duration(hours: 2), ph: 7.4),
      );
      await repository.insert(_reading(ph: 7.2));
      await repository.insert(
        _reading(offset: const Duration(hours: 1), ph: 7.3),
      );

      expect(
        (await repository.recent())
            .map((StoredReading s) => s.reading.ph)
            .toList(),
        <double?>[7.4, 7.3, 7.2],
      );
    });

    test('à horodatage égal, la plus récemment insérée passe devant', () async {
      // Une saisie et une trame de sonde peuvent tomber la même seconde :
      // l’ordre doit rester déterministe, pas dépendre du hasard du moteur.
      await repository.insert(_reading(ph: 7.2));
      await repository.insert(_reading(ph: 7.3));

      expect((await repository.recent()).first.reading.ph, 7.3);
    });

    test('recent borne à la limite, et jamais à moins d’une ligne', () async {
      for (int i = 0; i < 5; i++) {
        await repository.insert(
          _reading(
            offset: Duration(hours: i),
            ph: _phs[i],
          ),
        );
      }
      expect((await repository.recent(limit: 3)).length, 3);
      expect((await repository.recent(limit: 0)).length, 1);
      expect((await repository.recent(limit: -1)).length, 1);
    });

    test('latest filtre par origine', () async {
      await repository.insert(
        _reading(ph: 7.2, source: MeasurementSource.sensor),
      );
      await repository.insert(
        _reading(
          offset: const Duration(hours: 3),
          ph: 7.9,
          source: MeasurementSource.manual,
        ),
      );

      expect((await repository.latest())?.reading.ph, 7.9);
      expect(
        (await repository.latest(source: MeasurementSource.sensor))?.reading.ph,
        7.2,
      );
      expect(
        (await repository.latest(source: MeasurementSource.manual))?.reading.ph,
        7.9,
      );
    });

    test('latest rend null quand l’origine demandée est absente', () async {
      await repository.insert(
        _reading(ph: 7.2, source: MeasurementSource.manual),
      );
      expect(await repository.latest(source: MeasurementSource.sensor), isNull);
    });

    test('between trie chronologiquement, bornes incluses', () async {
      for (int i = 0; i < 4; i++) {
        await repository.insert(
          _reading(
            offset: Duration(hours: i),
            ph: _phs[i],
          ),
        );
      }

      final List<StoredReading> rows = await repository.between(
        from: _start.add(const Duration(hours: 1)),
        to: _start.add(const Duration(hours: 2)),
      );

      // Une courbe se lit de gauche à droite, du plus ancien au plus récent.
      expect(rows.map((StoredReading s) => s.reading.ph).toList(), <double?>[
        7.1,
        7.2,
      ]);
    });

    test('delete retire la bonne ligne et ignore une clé inconnue', () async {
      final StoredReading a = await repository.insert(_reading(ph: 7.2));
      await repository.insert(
        _reading(offset: const Duration(hours: 1), ph: 7.3),
      );

      await repository.delete(a.id);
      expect(await repository.count(), 1);
      expect((await repository.recent()).first.reading.ph, 7.3);

      await repository.delete(9999);
      expect(await repository.count(), 1);
    });

    test('deleteOlderThan purge strictement avant la date', () async {
      for (int day = 0; day < 5; day++) {
        await repository.insert(
          _reading(
            offset: Duration(days: day),
            ph: _phs[day],
          ),
        );
      }

      final int removed = await repository.deleteOlderThan(
        _start.add(const Duration(days: 2)),
      );

      // La borne elle-même est conservée : « antérieures à » est strict.
      expect(removed, 2);
      expect(await repository.count(), 3);
    });

    test('deleteOlderThan ne rend zéro que s’il n’y a rien à purger', () async {
      await repository.insert(_reading(ph: 7.2));
      expect(await repository.deleteOlderThan(_start), 0);
      expect(await repository.count(), 1);
    });
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // Le même contrat, exécuté sur la vraie base et sur le dépôt en mémoire.
  runContract('SQLite', () => ReadingsDatabase(path: inMemoryDatabasePath));
  runContract('mémoire', InMemoryReadingsRepository.new);
}
