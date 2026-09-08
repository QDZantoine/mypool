import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/devices/pool_device_driver.dart';
import '../data/readings_database.dart';
import '../models/water_reading.dart';

/// État de l'historique des mesures.
class ReadingsState {
  const ReadingsState({
    this.recent = const <StoredReading>[],
    this.isLoading = false,
    this.errorMessage,
  });

  /// Les mesures les plus récentes d'abord.
  final List<StoredReading> recent;

  final bool isLoading;

  /// Message en français, directement affichable.
  final String? errorMessage;

  /// La mesure la plus récente, toutes origines confondues.
  WaterReading? get latest => recent.isEmpty ? null : recent.first.reading;

  /// La dernière mesure de sonde, qui sert de référence à l'échantillonnage.
  ///
  /// Distincte de [latest] : une saisie manuelle ne doit pas empêcher
  /// d'enregistrer un point automatique, et inversement.
  WaterReading? get latestSensor => _latestOf(MeasurementSource.sensor);

  /// La dernière mesure SAISIE par l'utilisateur.
  ///
  /// C'est elle qui fait foi pour les recommandations, et non [latest] : la
  /// sonde s'enregistre toute seule et serait presque toujours la plus
  /// récente, ce qui masquerait la bandelette que l'utilisateur vient de lire.
  /// Une sonde ne mesure d'ailleurs ni le TAC, ni le TH, ni le stabilisant.
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

/// Historique des mesures : lecture, saisie, suppression.
///
/// N'effectue AUCUN calcul de dose. Il alimente les providers dérivés, qui
/// appellent les moteurs de `domain/`.
class WaterReadingsController extends StateNotifier<ReadingsState> {
  WaterReadingsController({
    required this._repository,
    this._pageSize = defaultPageSize,
  }) : super(const ReadingsState());

  /// Nombre de mesures gardées en mémoire.
  ///
  /// 200 points couvrent plusieurs mois de saisies hebdomadaires et plus d'une
  /// semaine d'échantillonnage automatique, ce qui dépasse largement ce qu'une
  /// courbe montre. Charger toute la table ferait grossir la mémoire sans rien
  /// apporter à l'écran.
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
      // Un historique illisible ne doit pas empêcher de saisir une mesure ni
      // de calculer une dose : on le signale et on continue à vide.
      state = ReadingsState(
        errorMessage: 'L’historique des mesures n’a pas pu être lu.',
        recent: state.recent,
      );
      _log(error);
    }
  }

  /// Enregistre une mesure saisie par l'utilisateur.
  Future<StoredReading?> record(WaterReading reading) async {
    if (reading.isEmpty) {
      // Rien de mesuré : enregistrer une ligne vide polluerait la courbe.
      return null;
    }
    try {
      final StoredReading stored = await _repository.insert(reading);
      // Insertion en tête : la liste est triée du plus récent au plus ancien,
      // et une mesure qu'on vient de saisir est la plus récente.
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

  /// Purge les mesures antérieures à une date, et recharge.
  ///
  /// La date entre par paramètre : ce contrôleur ne lit pas l'horloge, ce qui
  /// rend la purge testable et évite qu'un fuseau horaire décale la limite.
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

  /// Les mesures d'une période, pour la courbe d'historique.
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

  /// Détail technique conservé pour le diagnostic, jamais affiché.
  ///
  /// `avoid_print` est actif : la trace n'est pas écrite sur la console mais
  /// gardée en mémoire, où un écran de diagnostic pourra la lire.
  final List<String> technicalLog = <String>[];

  void _log(Object error) {
    if (error is DeviceException) {
      technicalLog.add(error.technicalDetail ?? error.message);
      return;
    }
    technicalLog.add('$error');
  }
}
