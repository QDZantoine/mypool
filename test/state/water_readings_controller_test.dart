import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/data/devices/pool_device_driver.dart';
import 'package:mypool/data/readings_database.dart';
import 'package:mypool/models/water_reading.dart';
import 'package:mypool/state/water_readings_controller.dart';

final DateTime _start = DateTime.utc(2026, 7, 15, 10);

WaterReading _reading({
  Duration offset = Duration.zero,
  double? ph = 7.2,
  MeasurementSource source = MeasurementSource.manual,
}) {
  return WaterReading(takenAt: _start.add(offset), ph: ph, source: source);
}

class _FailingRepository extends InMemoryReadingsRepository {
  bool failing = false;

  bool asDeviceException = false;

  void _check() {
    if (!failing) {
      return;
    }
    if (asDeviceException) {
      throw const DeviceException(
        'Le module ne répond pas.',
        technicalDetail: 'timeout sur la base',
      );
    }
    throw Exception('base verrouillée');
  }

  @override
  Future<StoredReading> insert(WaterReading reading) {
    _check();
    return super.insert(reading);
  }

  @override
  Future<List<StoredReading>> recent({int limit = 50}) {
    _check();
    return super.recent(limit: limit);
  }

  @override
  Future<void> delete(int id) {
    _check();
    return super.delete(id);
  }

  @override
  Future<int> deleteOlderThan(DateTime limit) {
    _check();
    return super.deleteOlderThan(limit);
  }

  @override
  Future<List<StoredReading>> between({
    required DateTime from,
    required DateTime to,
  }) {
    _check();
    return super.between(from: from, to: to);
  }
}

void main() {
  late InMemoryReadingsRepository repository;
  late WaterReadingsController controller;

  setUp(() {
    repository = InMemoryReadingsRepository();
    controller = WaterReadingsController(repository: repository);
  });

  tearDown(() {
    controller.dispose();
  });

  group('chargement', () {
    test('l’état initial est vide, sans erreur', () {
      expect(controller.state.isEmpty, isTrue);
      expect(controller.state.latest, isNull);
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.isLoading, isFalse);
    });

    test('load rend les mesures les plus récentes d’abord', () async {
      await repository.insert(_reading(ph: 7.2));
      await repository.insert(
        _reading(offset: const Duration(hours: 1), ph: 7.4),
      );

      await controller.load();

      expect(controller.state.recent.length, 2);
      expect(controller.state.latest?.ph, 7.4);
      expect(controller.state.isLoading, isFalse);
    });

    test('load respecte la taille de page', () async {
      final WaterReadingsController small = WaterReadingsController(
        repository: repository,
        pageSize: 2,
      );
      addTearDown(small.dispose);

      for (int i = 0; i < 5; i++) {
        await repository.insert(_reading(offset: Duration(hours: i)));
      }
      await small.load();

      expect(small.state.recent.length, 2);
    });
  });

  group('saisie', () {
    test('record insère en tête de liste et en base', () async {
      final StoredReading? stored = await controller.record(_reading(ph: 7.8));

      expect(stored, isNotNull);
      expect(controller.state.recent.length, 1);
      expect(controller.state.latest?.ph, 7.8);
      expect(await repository.count(), 1);
    });

    test('une mesure vide n’est pas enregistrée', () async {

      final StoredReading? stored = await controller.record(
        WaterReading(takenAt: _start),
      );

      expect(stored, isNull);
      expect(controller.state.isEmpty, isTrue);
      expect(await repository.count(), 0);
    });

    test('la mesure saisie devient la plus récente affichée', () async {
      await controller.load();
      await controller.record(_reading(ph: 7.1));
      await controller.record(
        _reading(offset: const Duration(hours: 2), ph: 7.9),
      );

      expect(controller.state.latest?.ph, 7.9);
      expect(controller.state.recent.first.reading.ph, 7.9);
    });
  });

  group('origine des mesures', () {
    test('latestSensor ignore les saisies manuelles', () async {

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
      await controller.load();

      expect(controller.state.latest?.ph, 7.9);
      expect(controller.state.latestSensor?.ph, 7.2);
    });

    test('latestSensor rend null sans aucune mesure de sonde', () async {
      await controller.record(_reading(ph: 7.2));
      expect(controller.state.latestSensor, isNull);
    });
  });

  group('suppression et purge', () {
    test('delete retire la mesure de la liste et de la base', () async {
      final StoredReading? a = await controller.record(_reading(ph: 7.2));
      await controller.record(
        _reading(offset: const Duration(hours: 1), ph: 7.4),
      );

      await controller.delete(a!.id);

      expect(controller.state.recent.length, 1);
      expect(controller.state.latest?.ph, 7.4);
      expect(await repository.count(), 1);
    });

    test('purgeBefore supprime, recharge et rend le compte', () async {
      for (int day = 0; day < 5; day++) {
        await repository.insert(_reading(offset: Duration(days: day)));
      }
      await controller.load();

      final int removed = await controller.purgeBefore(
        _start.add(const Duration(days: 2)),
      );

      expect(removed, 2);
      expect(controller.state.recent.length, 3);
    });
  });

  group('lecture d’une période', () {
    test('between rend la période dans l’ordre chronologique', () async {
      for (int i = 0; i < 4; i++) {
        await repository.insert(_reading(offset: Duration(hours: i)));
      }

      final List<StoredReading> rows = await controller.between(
        from: _start.add(const Duration(hours: 1)),
        to: _start.add(const Duration(hours: 2)),
      );

      expect(rows.length, 2);
      expect(rows.first.reading.takenAt, _start.add(const Duration(hours: 1)));
    });
  });

  group('panne de base', () {
    late _FailingRepository failing;

    setUp(() {
      failing = _FailingRepository();
      controller = WaterReadingsController(repository: failing);
    });

    test('une lecture qui échoue laisse un message affichable', () async {
      failing.failing = true;
      await controller.load();

      expect(controller.state.errorMessage, contains('historique'));
      expect(controller.state.errorMessage, isNot(contains('Exception')));
      expect(controller.state.isLoading, isFalse);

      expect(controller.technicalLog, isNotEmpty);
      expect(controller.technicalLog.first, contains('verrouillée'));
    });

    test('une écriture qui échoue rend null et le signale', () async {
      failing.failing = true;
      final StoredReading? stored = await controller.record(_reading());

      expect(stored, isNull);
      expect(controller.state.errorMessage, contains('enregistrée'));
    });

    test('une suppression qui échoue laisse la liste en place', () async {
      final StoredReading? a = await controller.record(_reading());
      failing.failing = true;

      await controller.delete(a!.id);

      expect(controller.state.recent.length, 1);
      expect(controller.state.errorMessage, contains('supprimée'));
    });

    test('une purge qui échoue rend zéro', () async {
      failing.failing = true;
      expect(await controller.purgeBefore(_start), 0);
      expect(controller.state.errorMessage, contains('purge'));
    });

    test('une lecture de période qui échoue rend une liste vide', () async {
      failing.failing = true;
      expect(await controller.between(from: _start, to: _start), isEmpty);
      expect(controller.technicalLog, isNotEmpty);
    });

    test('une erreur matérielle garde son détail technique à part', () async {

      failing.failing = true;
      failing.asDeviceException = true;

      await controller.load();

      expect(controller.state.errorMessage, contains('historique'));
      expect(controller.technicalLog.first, 'timeout sur la base');
    });

    test('l’erreur est effacée par une opération réussie', () async {
      failing.failing = true;
      await controller.load();
      expect(controller.state.errorMessage, isNotNull);

      failing.failing = false;
      await controller.record(_reading());
      expect(controller.state.errorMessage, isNull);
    });
  });

  group('état exposé', () {
    test('toString reste lisible en journal', () async {
      await controller.record(_reading());
      expect(controller.state.toString(), contains('1 mesure'));
    });

    test('copyWith efface l’erreur sur demande', () {
      const ReadingsState state = ReadingsState(errorMessage: 'panne');
      expect(state.copyWith(clearError: true).errorMessage, isNull);
      expect(state.copyWith().errorMessage, 'panne');
    });
  });
}
