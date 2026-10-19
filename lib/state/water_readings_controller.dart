import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/devices/pool_device_driver.dart';
import '../data/readings_database.dart';
import '../models/water_reading.dart';

class ReadingsState {
  const ReadingsState({
    this.recent = const <StoredReading>[],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<StoredReading> recent;

  final bool isLoading;

  final String? errorMessage;

  WaterReading? get latest => recent.isEmpty ? null : recent.first.reading;

  WaterReading? get latestSensor => _latestOf(MeasurementSource.sensor);

  WaterReading? get latestManual => _latestOf(MeasurementSource.manual);

  WaterReading? _latestOf(MeasurementSource source) {
    for (final StoredReading stored in recent) {
      if (stored.reading.source == source) {
        return stored.reading;
      }
    }
    return null;
  }

  bool get isEmpty => recent.isEmpty;

  ReadingsState copyWith({
    List<StoredReading>? recent,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ReadingsState(
      recent: recent ?? this.recent,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  String toString() =>
      'ReadingsState(${recent.length} mesures, chargement: $isLoading)';
}

class WaterReadingsController extends StateNotifier<ReadingsState> {
  WaterReadingsController({
    required this._repository,
    this._pageSize = defaultPageSize,
  }) : super(const ReadingsState());

  static const int defaultPageSize = 200;

  final ReadingsRepository _repository;
  final int _pageSize;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final List<StoredReading> rows = await _repository.recent(
        limit: _pageSize,
      );
      state = ReadingsState(recent: rows);
    } on Object catch (error) {

      state = ReadingsState(
        errorMessage: 'L’historique des mesures n’a pas pu être lu.',
        recent: state.recent,
      );
      _log(error);
    }
  }

  Future<StoredReading?> record(WaterReading reading) async {
    if (reading.isEmpty) {

      return null;
    }
    try {
      final StoredReading stored = await _repository.insert(reading);

      state = state.copyWith(
        recent: <StoredReading>[stored, ...state.recent],
        clearError: true,
      );
      return stored;
    } on Object catch (error) {
      state = state.copyWith(
        errorMessage: 'La mesure n’a pas pu être enregistrée.',
      );
      _log(error);
      return null;
    }
  }

  Future<void> delete(int id) async {
    try {
      await _repository.delete(id);
      state = state.copyWith(
        recent: state.recent
            .where((StoredReading s) => s.id != id)
            .toList(growable: false),
        clearError: true,
      );
    } on Object catch (error) {
      state = state.copyWith(
        errorMessage: 'La mesure n’a pas pu être supprimée.',
      );
      _log(error);
    }
  }

  Future<int> purgeBefore(DateTime limit) async {
    try {
      final int removed = await _repository.deleteOlderThan(limit);
      await load();
      return removed;
    } on Object catch (error) {
      state = state.copyWith(errorMessage: 'La purge a échoué.');
      _log(error);
      return 0;
    }
  }

  Future<List<StoredReading>> between({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      return await _repository.between(from: from, to: to);
    } on Object catch (error) {
      _log(error);
      return const <StoredReading>[];
    }
  }

  final List<String> technicalLog = <String>[];

  void _log(Object error) {
    if (error is DeviceException) {
      technicalLog.add(error.technicalDetail ?? error.message);
      return;
    }
    technicalLog.add('$error');
  }
}
