import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/water_reading.dart';

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

abstract class ReadingsRepository {
  Future<StoredReading> insert(WaterReading reading);

  Future<List<StoredReading>> recent({int limit});

  Future<StoredReading?> latest({MeasurementSource? source});

  Future<List<StoredReading>> between({
    required DateTime from,
    required DateTime to,
  });

  Future<void> delete(int id);

  Future<int> deleteOlderThan(DateTime limit);

  Future<int> count();

  Future<void> close();
}

class ReadingsDatabase implements ReadingsRepository {
  ReadingsDatabase({this._path});

  static const String tableName = 'readings';

  static const int schemaVersion = 1;

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

    await db.execute(
      'CREATE INDEX idx_${tableName}_taken_at ON $tableName (taken_at DESC)',
    );
  }

  static Future<void> migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {

  }

  static Map<String, Object?> toRow(WaterReading reading) {
    return <String, Object?>{

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
