import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/water_reading.dart';

/// Une mesure telle qu'elle est stockée : son contenu, et sa clé.
///
/// L'identifiant vit ici et non dans [WaterReading] : le modèle traverse
/// toutes les couches et ne doit rien savoir de la base. Sans clé, supprimer
/// une mesure supposerait que deux mesures n'ont jamais le même horodatage,
/// ce qui est faux dès qu'une saisie et une trame de sonde tombent la même
/// seconde.
class StoredReading {
  const StoredReading({required this.id, required this.reading});

  final int id;
  final WaterReading reading;

  @override
  bool operator ==(Object other) =>
      other is StoredReading && other.id == id && other.reading == reading;

  @override
  int get hashCode => Object.hash(id, reading);

  @override
  String toString() => 'StoredReading($id, ${reading.takenAt})';
}

/// Ce dont l'application a besoin de l'historique des mesures.
///
/// L'interface permet de tester les contrôleurs sans base, et laisserait
/// changer de moteur de stockage sans toucher aux couches au-dessus.
abstract class ReadingsRepository {
  Future<StoredReading> insert(WaterReading reading);

  /// Les mesures les plus récentes d'abord.
  Future<List<StoredReading>> recent({int limit});

  /// La dernière mesure enregistrée, éventuellement filtrée par origine.
  ///
  /// Le filtre par origine sert à la règle d'échantillonnage : une saisie
  /// manuelle ne doit pas empêcher d'enregistrer un point de sonde, et
  /// inversement.
  Future<StoredReading?> latest({MeasurementSource? source});

  /// Les mesures d'une période, dans l'ordre chronologique.
  ///
  /// Ordre croissant parce que c'est celui d'une courbe : l'historique
  /// s'affiche du plus ancien au plus récent, de gauche à droite.
  Future<List<StoredReading>> between({
    required DateTime from,
    required DateTime to,
  });

  Future<void> delete(int id);

  /// Purge les mesures antérieures à une date.
  Future<int> deleteOlderThan(DateTime limit);

  Future<int> count();

  Future<void> close();
}

/// Historique des mesures, en SQLite.
///
/// Les horodatages sont stockés en millisecondes UTC depuis l'époque Unix, et
/// non en texte : c'est comparable et triable en SQL sans dépendre du format
/// de date, et cela évite le piège du décalage horaire au changement d'heure.
class ReadingsDatabase implements ReadingsRepository {
  ReadingsDatabase({this._path});

  static const String tableName = 'readings';

  /// Version du schéma. Toute évolution incompatible l'incrémente et ajoute sa
  /// migration dans [_upgrade].
  static const int schemaVersion = 1;

  /// Nom du fichier de base sur l'appareil.
  static const String fileName = 'aquacontrol.db';

  final String? _path;
  Database? _database;

  Future<Database> _open() async {
    final Database? existing = _database;
    if (existing != null) {
      return existing;
    }
    final String path = _path ?? p.join(await getDatabasesPath(), fileName);
    final Database database = await openDatabase(
      path,
      version: schemaVersion,
      onCreate: _create,
      onUpgrade: migrate,
    );
    _database = database;
    return database;
  }

  Future<void> _create(Database db, int version) async {
    // Toutes les mesures sont facultatives : on saisit ce qu'on a mesuré, et
    // une colonne NULL veut dire « non mesuré », jamais « zéro ».
    await db.execute('''
      CREATE TABLE $tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        taken_at INTEGER NOT NULL,
        ph REAL,
        free_chlorine REAL,
        combined_chlorine REAL,
        tac REAL,
        th REAL,
        stabilizer REAL,
        salt REAL,
        temperature REAL,
        note TEXT,
        source TEXT NOT NULL DEFAULT '${MeasurementSource.manual.name}'
      )
    ''');

    // L'historique se lit toujours par date décroissante, et la courbe par
    // plage de dates : sans cet index, chaque affichage relit toute la table.
    await db.execute(
      'CREATE INDEX idx_${tableName}_taken_at ON $tableName (taken_at DESC)',
    );
  }

  /// Migrations de schéma.
  ///
  /// Aucune à ce jour : le schéma est en version 1 et le champ `source` y
  /// figure dès l'origine, parce qu'il a été ajouté au modèle avant que la
  /// base n'existe. La méthode est publique pour deux raisons : la première
  /// migration a déjà sa place, et elle reste vérifiable par un test sans
  /// avoir à fabriquer une base d'une version antérieure qui n'a jamais
  /// existé.
  static Future<void> migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // À compléter au premier changement de schéma, en enchaînant les paliers :
    //   if (oldVersion < 2) { await db.execute('ALTER TABLE ...'); }
  }

  /// Traduit une mesure en ligne de table.
  static Map<String, Object?> toRow(WaterReading reading) {
    return <String, Object?>{
      // Stocké en UTC : une base relue après un voyage ou un changement
      // d'heure doit rendre les mêmes instants.
      'taken_at': reading.takenAt.toUtc().millisecondsSinceEpoch,
      'ph': reading.ph,
      'free_chlorine': reading.freeChlorine,
      'combined_chlorine': reading.combinedChlorine,
      'tac': reading.tac,
      'th': reading.th,
      'stabilizer': reading.stabilizer,
      'salt': reading.salt,
      'temperature': reading.temperature,
      'note': reading.note,
      'source': reading.source.name,
    };
  }

  /// Reconstruit une mesure depuis une ligne.
  ///
  /// Tolérant, pour la même raison que les `fromJson` : une base écrite par
  /// une version antérieure, ou une ligne modifiée à la main, ne doit pas
  /// faire échouer l'affichage de tout l'historique.
  static StoredReading fromRow(Map<String, Object?> row) {
    return StoredReading(
      id: _asInt(row['id']) ?? 0,
      reading: WaterReading(
        takenAt: DateTime.fromMillisecondsSinceEpoch(
          _asInt(row['taken_at']) ?? 0,
          isUtc: true,
        ),
        ph: _asDouble(row['ph']),
        freeChlorine: _asDouble(row['free_chlorine']),
        combinedChlorine: _asDouble(row['combined_chlorine']),
        tac: _asDouble(row['tac']),
        th: _asDouble(row['th']),
        stabilizer: _asDouble(row['stabilizer']),
        salt: _asDouble(row['salt']),
        temperature: _asDouble(row['temperature']),
        note: _asString(row['note']),
        source: _asSource(row['source']),
      ),
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static double? _asDouble(Object? value) {
    if (value is num) {
      final double result = value.toDouble();
      return result.isFinite ? result : null;
    }
    if (value is String) {
      final double? parsed = double.tryParse(value);
      return (parsed != null && parsed.isFinite) ? parsed : null;
    }
    return null;
  }

  static String? _asString(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return null;
  }

  /// Une origine illisible vaut « saisie » : on ne prête pas à une mesure la
  /// crédibilité d'une sonde sans preuve.
  static MeasurementSource _asSource(Object? value) {
    if (value is String) {
      for (final MeasurementSource source in MeasurementSource.values) {
        if (source.name == value) {
          return source;
        }
      }
    }
    return MeasurementSource.manual;
  }

  @override
  Future<StoredReading> insert(WaterReading reading) async {
    final Database db = await _open();
    final int id = await db.insert(tableName, toRow(reading));
    return StoredReading(id: id, reading: reading);
  }

  @override
  Future<List<StoredReading>> recent({int limit = 50}) async {
    final Database db = await _open();
    final List<Map<String, Object?>> rows = await db.query(
      tableName,
      orderBy: 'taken_at DESC, id DESC',
      // Une limite non positive ramènerait toute la table sur un écran qui
      // n'en montre qu'une poignée.
      limit: limit < 1 ? 1 : limit,
    );
    return rows.map(fromRow).toList(growable: false);
  }

  @override
  Future<StoredReading?> latest({MeasurementSource? source}) async {
    final Database db = await _open();
    final List<Map<String, Object?>> rows = await db.query(
      tableName,
      where: source == null ? null : 'source = ?',
      whereArgs: source == null ? null : <Object?>[source.name],
      orderBy: 'taken_at DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return fromRow(rows.first);
  }

  @override
  Future<List<StoredReading>> between({
    required DateTime from,
    required DateTime to,
  }) async {
    final Database db = await _open();
    // Bornes incluses : une plage « du 1er au 7 » doit contenir les mesures
    // prises exactement à ces instants.
    final List<Map<String, Object?>> rows = await db.query(
      tableName,
      where: 'taken_at >= ? AND taken_at <= ?',
      whereArgs: <Object?>[
        from.toUtc().millisecondsSinceEpoch,
        to.toUtc().millisecondsSinceEpoch,
      ],
      orderBy: 'taken_at ASC, id ASC',
    );
    return rows.map(fromRow).toList(growable: false);
  }

  @override
  Future<void> delete(int id) async {
    final Database db = await _open();
    await db.delete(tableName, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  @override
  Future<int> deleteOlderThan(DateTime limit) async {
    final Database db = await _open();
    return db.delete(
      tableName,
      where: 'taken_at < ?',
      whereArgs: <Object?>[limit.toUtc().millisecondsSinceEpoch],
    );
  }

  @override
  Future<int> count() async {
    final Database db = await _open();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM $tableName',
    );
    return _asInt(rows.first['total']) ?? 0;
  }

  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

/// Historique en mémoire, pour les tests des couches au-dessus.
///
/// Reproduit les mêmes ordres de tri et les mêmes bornes que la base réelle :
/// un test qui passe ici doit passer sur SQLite, et c'est ce que vérifient les
/// tests de [ReadingsDatabase].
class InMemoryReadingsRepository implements ReadingsRepository {
  final List<StoredReading> _rows = <StoredReading>[];
  int _nextId = 1;

  @override
  Future<StoredReading> insert(WaterReading reading) async {
    final StoredReading stored = StoredReading(id: _nextId++, reading: reading);
    _rows.add(stored);
    return stored;
  }

  List<StoredReading> get _byDateDesc {
    final List<StoredReading> sorted = List<StoredReading>.from(_rows);
    sorted.sort((StoredReading a, StoredReading b) {
      final int byDate = b.reading.takenAt.compareTo(a.reading.takenAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
    return sorted;
  }

  @override
  Future<List<StoredReading>> recent({int limit = 50}) async {
    return _byDateDesc.take(limit < 1 ? 1 : limit).toList(growable: false);
  }

  @override
  Future<StoredReading?> latest({MeasurementSource? source}) async {
    for (final StoredReading stored in _byDateDesc) {
      if (source == null || stored.reading.source == source) {
        return stored;
      }
    }
    return null;
  }

  @override
  Future<List<StoredReading>> between({
    required DateTime from,
    required DateTime to,
  }) async {
    final List<StoredReading> kept = _rows
        .where(
          (StoredReading s) =>
              !s.reading.takenAt.isBefore(from) &&
              !s.reading.takenAt.isAfter(to),
        )
        .toList();
    kept.sort((StoredReading a, StoredReading b) {
      final int byDate = a.reading.takenAt.compareTo(b.reading.takenAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return List<StoredReading>.unmodifiable(kept);
  }

  @override
  Future<void> delete(int id) async {
    _rows.removeWhere((StoredReading s) => s.id == id);
  }

  @override
  Future<int> deleteOlderThan(DateTime limit) async {
    final int before = _rows.length;
    _rows.removeWhere((StoredReading s) => s.reading.takenAt.isBefore(limit));
    return before - _rows.length;
  }

  @override
  Future<int> count() async => _rows.length;

  @override
  Future<void> close() async {
    _rows.clear();
  }
}
