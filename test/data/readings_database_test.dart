import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/readings_database.dart';
import 'package:mypool/models/water_reading.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final DateTime _start = DateTime.utc(2026, 7, 15, 10);

WaterReading _reading({
  Duration offset = Duration.zero,
  double? ph,
  double? temperature,
  MeasurementSource source = MeasurementSource.manual,
  String? note,
}) {
  return WaterReading(
    takenAt: _start.add(offset),
    ph: ph,
    temperature: temperature,
    source: source,
    note: note,
  );
}

void main() {
  // Un vrai SQLite, en mémoire : les requêtes sont réellement exécutées, pas
  // simulées. Une erreur de SQL se voit ici et non sur un téléphone.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late ReadingsDatabase database;

  setUp(() {
    database = ReadingsDatabase(path: inMemoryDatabasePath);
  });

  tearDown(() async {
    await database.close();
  });

  group('schéma', () {
    test('la table et son index sont créés', () async {
      // Une insertion suffit à déclencher l'ouverture et la création.
      await database.insert(_reading(ph: 7.2));

      final Database db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      // On interroge la base réellement ouverte par le dépôt.
      expect(await database.count(), 1);
      expect(ReadingsDatabase.schemaVersion, 1);
    });

    test('la migration ne touche à rien en version 1', () async {
      // Le schéma est en version 1 et le champ `source` y figure dès
      // l'origine : il n'y a rien à migrer. Le test verrouille cet état, et
      // échouera le jour où une migration sera ajoutée sans être vérifiée.
      await database.insert(
        _reading(ph: 7.2, source: MeasurementSource.sensor),
      );
      final Database db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);

      await ReadingsDatabase.migrate(db, 1, 1);

      expect(await database.count(), 1);
      expect(
        (await database.recent()).first.reading.source,
        MeasurementSource.sensor,
      );
    });

    test('une base vide ne compte aucune mesure', () async {
      expect(await database.count(), 0);
      expect(await database.recent(), isEmpty);
      expect(await database.latest(), isNull);
    });
  });

  group('aller-retour en base', () {
    test('une mesure complète est restituée à l’identique', () async {
      final WaterReading original = WaterReading(
        takenAt: _start,
        ph: 7.35,
        freeChlorine: 1.8,
        combinedChlorine: 0.15,
        tac: 105.0,
        th: 240.0,
        stabilizer: 35.0,
        salt: 4.2,
        temperature: 27.5,
        note: 'après un orage',
        source: MeasurementSource.sensor,
      );

      final StoredReading stored = await database.insert(original);
      expect(stored.id, greaterThan(0));

      final List<StoredReading> rows = await database.recent();
      expect(rows.length, 1);
      expect(rows.first.reading, original);
      expect(rows.first.id, stored.id);
    });

    test(
      'une valeur non mesurée reste absente, elle ne devient pas zéro',
      () async {
        // Le point essentiel du schéma : une colonne NULL veut dire « non
        // mesuré ». Un zéro ferait calculer une correction massive.
        await database.insert(WaterReading(takenAt: _start, ph: 7.2));

        final WaterReading restored = (await database.recent()).first.reading;
        expect(restored.ph, 7.2);
        expect(restored.tac, isNull);
        expect(restored.freeChlorine, isNull);
        expect(restored.temperature, isNull);
        expect(restored.note, isNull);
      },
    );

    test('l’origine par défaut est la saisie', () async {
      await database.insert(WaterReading(takenAt: _start, ph: 7.2));
      expect(
        (await database.recent()).first.reading.source,
        MeasurementSource.manual,
      );
    });

    test('les horodatages sont stockés en UTC', () async {
      // Une base relue après un changement d’heure ou un voyage doit rendre
      // les mêmes instants.
      final DateTime local = DateTime(2026, 7, 15, 10, 30);
      await database.insert(WaterReading(takenAt: local, ph: 7.2));

      final DateTime restored = (await database.recent()).first.reading.takenAt;
      expect(restored.isUtc, isTrue);
      expect(
        restored.millisecondsSinceEpoch,
        local.toUtc().millisecondsSinceEpoch,
      );
    });

    test('chaque insertion reçoit une clé distincte', () async {
      // Deux mesures au même instant : une saisie et une trame de sonde
      // peuvent tomber la même seconde.
      final StoredReading a = await database.insert(
        _reading(ph: 7.2, source: MeasurementSource.manual),
      );
      final StoredReading b = await database.insert(
        _reading(ph: 7.3, source: MeasurementSource.sensor),
      );

      expect(a.id, isNot(b.id));
      expect(await database.count(), 2);
    });
  });

  group('lecture de l’historique', () {
    setUp(() async {
      // Trois mesures, insérées dans le désordre chronologique.
      await database.insert(
        _reading(offset: const Duration(hours: 2), ph: 7.4),
      );
      await database.insert(_reading(ph: 7.2));
      await database.insert(
        _reading(offset: const Duration(hours: 1), ph: 7.3),
      );
    });

    test('recent rend les plus récentes d’abord', () async {
      final List<StoredReading> rows = await database.recent();
      expect(rows.map((StoredReading s) => s.reading.ph).toList(), <double?>[
        7.4,
        7.3,
        7.2,
      ]);
    });

    test('recent respecte la limite', () async {
      expect((await database.recent(limit: 2)).length, 2);
      expect((await database.recent(limit: 2)).first.reading.ph, 7.4);
      // Une limite non positive ne doit pas ramener toute la table.
      expect((await database.recent(limit: 0)).length, 1);
      expect((await database.recent(limit: -5)).length, 1);
    });

    test('latest rend la plus récente', () async {
      expect((await database.latest())?.reading.ph, 7.4);
    });

    test('between rend la période dans l’ordre chronologique', () async {
      // Une courbe se lit du plus ancien au plus récent, de gauche à droite.
      final List<StoredReading> rows = await database.between(
        from: _start,
        to: _start.add(const Duration(hours: 2)),
      );
      expect(rows.map((StoredReading s) => s.reading.ph).toList(), <double?>[
        7.2,
        7.3,
        7.4,
      ]);
    });

    test('les bornes de between sont incluses', () async {
      // Une plage « du 1er au 7 » doit contenir les mesures prises exactement
      // à ces instants.
      final List<StoredReading> rows = await database.between(
        from: _start.add(const Duration(hours: 1)),
        to: _start.add(const Duration(hours: 1)),
      );
      expect(rows.length, 1);
      expect(rows.first.reading.ph, 7.3);
    });

    test('une période sans mesure rend une liste vide', () async {
      final List<StoredReading> rows = await database.between(
        from: _start.add(const Duration(days: 10)),
        to: _start.add(const Duration(days: 11)),
      );
      expect(rows, isEmpty);
    });
  });

  group('filtre par origine', () {
    test('latest distingue saisie et sonde', () async {
      // La règle d’échantillonnage a besoin de la dernière mesure de SONDE :
      // une saisie manuelle ne doit pas empêcher d’enregistrer un point
      // automatique.
      await database.insert(
        _reading(ph: 7.2, source: MeasurementSource.sensor),
      );
      await database.insert(
        _reading(
          offset: const Duration(hours: 3),
          ph: 7.9,
          source: MeasurementSource.manual,
        ),
      );

      expect((await database.latest())?.reading.ph, 7.9);
      expect(
        (await database.latest(source: MeasurementSource.sensor))?.reading.ph,
        7.2,
      );
      expect(
        (await database.latest(source: MeasurementSource.manual))?.reading.ph,
        7.9,
      );
    });

    test('latest rend null si aucune mesure de cette origine', () async {
      await database.insert(
        _reading(ph: 7.2, source: MeasurementSource.manual),
      );
      expect(await database.latest(source: MeasurementSource.sensor), isNull);
    });
  });

  group('suppression', () {
    test('delete retire une mesure par sa clé', () async {
      final StoredReading a = await database.insert(_reading(ph: 7.2));
      await database.insert(
        _reading(offset: const Duration(hours: 1), ph: 7.3),
      );

      await database.delete(a.id);

      expect(await database.count(), 1);
      expect((await database.recent()).first.reading.ph, 7.3);
    });

    test('delete sur une clé inconnue ne fait rien', () async {
      await database.insert(_reading(ph: 7.2));
      await database.delete(9999);
      expect(await database.count(), 1);
    });

    test(
      'deleteOlderThan purge et rend le nombre de lignes supprimées',
      () async {
        for (int day = 0; day < 5; day++) {
          await database.insert(
            _reading(
              offset: Duration(days: day),
              ph: 7.0 + day * 0.1,
            ),
          );
        }

        final int removed = await database.deleteOlderThan(
          _start.add(const Duration(days: 2)),
        );

        // Les jours 0 et 1 partent, la borne du jour 2 reste.
        expect(removed, 2);
        expect(await database.count(), 3);
        expect((await database.recent()).last.reading.ph, closeTo(7.2, 1e-9));
      },
    );
  });

  group('tolérance à une base abîmée', () {
    test('une ligne aux types inattendus reste lisible', () async {
      // Une base écrite par une version antérieure, ou modifiée à la main, ne
      // doit pas faire échouer l’affichage de tout l’historique.
      final StoredReading stored = ReadingsDatabase.fromRow(<String, Object?>{
        'id': '42',
        'taken_at': '1770000000000',
        'ph': '7.4',
        'tac': 'beaucoup',
        'th': true,
        'note': '   ',
        'source': 'télépathie',
      });

      expect(stored.id, 42);
      expect(stored.reading.takenAt.millisecondsSinceEpoch, 1770000000000);
      expect(stored.reading.ph, 7.4);
      // Illisible devient absent, pas zéro.
      expect(stored.reading.tac, isNull);
      expect(stored.reading.th, isNull);
      expect(stored.reading.note, isNull);
      // Une origine inconnue vaut « saisie » : on ne prête pas à une mesure
      // la crédibilité d’une sonde sans preuve.
      expect(stored.reading.source, MeasurementSource.manual);
    });

    test(
      'une ligne vide rend une mesure vide datée de l’époque Unix',
      () async {
        final StoredReading stored = ReadingsDatabase.fromRow(
          <String, Object?>{},
        );
        expect(stored.id, 0);
        expect(stored.reading.isEmpty, isTrue);
        expect(stored.reading.takenAt.millisecondsSinceEpoch, 0);
      },
    );

    test('un entier stocké en réel est arrondi', () async {
      // SQLite peut rendre un INTEGER sous forme de double après un calcul.
      final StoredReading stored = ReadingsDatabase.fromRow(<String, Object?>{
        'id': 42.7,
        'taken_at': 1770000000000.0,
      });
      expect(stored.id, 43);
      expect(stored.reading.takenAt.millisecondsSinceEpoch, 1770000000000);
    });

    test('un NaN stocké devient absent', () async {
      final StoredReading stored = ReadingsDatabase.fromRow(<String, Object?>{
        'ph': double.nan,
        'tac': double.infinity,
      });
      expect(stored.reading.ph, isNull);
      expect(stored.reading.tac, isNull);
    });

    test('toRow et fromRow font l’aller-retour', () async {
      final WaterReading original = WaterReading(
        takenAt: _start,
        ph: 7.2,
        tac: 100.0,
        source: MeasurementSource.sensor,
        note: 'bandelette',
      );
      final Map<String, Object?> row = ReadingsDatabase.toRow(original);
      final StoredReading restored = ReadingsDatabase.fromRow(row);
      expect(restored.reading, original);
    });
  });

  group('cycle de vie', () {
    test('la base se réouvre après fermeture', () async {
      await database.insert(_reading(ph: 7.2));
      await database.close();
      // Réouverture : une base en mémoire repart vide, ce qui suffit à
      // vérifier qu'aucune exception n'est levée.
      expect(await database.count(), 0);
    });

    test('deux lectures consécutives réutilisent la même connexion', () async {
      await database.insert(_reading(ph: 7.2));
      expect(await database.count(), 1);
      expect(await database.count(), 1);
    });
  });

  group('StoredReading', () {
    test('égalité sur la clé et le contenu', () async {
      final WaterReading reading = _reading(ph: 7.2);
      expect(
        StoredReading(id: 1, reading: reading),
        StoredReading(id: 1, reading: reading),
      );
      expect(
        StoredReading(id: 1, reading: reading).hashCode,
        StoredReading(id: 1, reading: reading).hashCode,
      );
      expect(
        StoredReading(id: 1, reading: reading),
        isNot(StoredReading(id: 2, reading: reading)),
      );
      expect(StoredReading(id: 1, reading: reading) == Object(), isFalse);
    });

    test('toString reste lisible en journal', () async {
      expect(
        StoredReading(id: 7, reading: _reading(ph: 7.2)).toString(),
        allOf(contains('7'), contains('2026')),
      );
    });
  });
}
