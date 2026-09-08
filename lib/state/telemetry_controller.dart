import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/devices/pool_device_driver.dart';
import '../data/devices/telemetry.dart';
import '../data/devices/wokwi_mqtt_driver.dart';
import '../domain/reading_sampler.dart';
import '../models/water_reading.dart';

/// État de la liaison au module et dernière mesure reçue.
class TelemetryState {
  const TelemetryState({
    this.telemetry,
    this.isModuleOnline = false,
    this.isFresh = false,
    this.filterAlert = false,
    this.errorMessage,
  });

  /// Dernière trame reçue, quel que soit son âge.
  final PoolTelemetry? telemetry;

  /// Le module a-t-il annoncé sa présence, ou son testament ?
  final bool isModuleOnline;

  /// La dernière trame est-elle assez récente pour être affichée comme
  /// l'état courant ?
  ///
  /// Distinct de [isModuleOnline] : le téléphone peut être connecté au broker
  /// alors que l'ESP32 est débranché, et inversement une trame retenue peut
  /// arriver d'un module déjà éteint.
  final bool isFresh;

  final bool filterAlert;

  final String? errorMessage;

  /// Y a-t-il quelque chose à afficher en direct ?
  bool get hasLiveValues => isFresh && telemetry != null;

  /// pH mesuré en direct, ou `null` si la liaison ne fait pas foi.
  double? get livePh => hasLiveValues ? telemetry!.ph : null;

  /// Température mesurée en direct, ou `null`.
  double? get liveTemperatureC =>
      hasLiveValues ? telemetry!.temperatureC : null;

  TelemetryState copyWith({
    PoolTelemetry? telemetry,
    bool? isModuleOnline,
    bool? isFresh,
    bool? filterAlert,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TelemetryState(
      telemetry: telemetry ?? this.telemetry,
      isModuleOnline: isModuleOnline ?? this.isModuleOnline,
      isFresh: isFresh ?? this.isFresh,
      filterAlert: filterAlert ?? this.filterAlert,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  String toString() =>
      'TelemetryState(en ligne: $isModuleOnline, '
      'frais: $isFresh, pH ${telemetry?.ph})';
}

/// Suit la télémétrie du module et décide de ce qui entre dans l'historique.
///
/// N'effectue AUCUN calcul métier : la règle d'échantillonnage vit dans
/// [ReadingSampler], qui est pur. Ce contrôleur se contente d'appeler la
/// règle, d'enregistrer ce qu'elle retient, et d'exposer l'état courant.
///
/// Le problème résolu : le module publie une trame toutes les 2 s, soit
/// 43 200 par jour. Elles alimentent un état COURANT affiché en direct et non
/// persisté ; seules celles que la règle retient entrent dans l'historique
/// (addendum § 5).
class TelemetryController extends StateNotifier<TelemetryState> {
  TelemetryController({
    required this._driver,
    required this._onSample,
    required this._lastSensorReading,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const TelemetryState());

  /// Pilote MQTT, ou `null` quand la liaison choisie n'est pas MQTT.
  ///
  /// Le `null` n'est pas une panne : une piscine en simulation ou sur module
  /// local n'a simplement pas de télémétrie. Le contrôleur reste alors inerte,
  /// sans message d'erreur, et les écrans affichent l'absence de mesures en
  /// direct comme un état normal.
  final WokwiMqttDriver? _driver;

  /// Enregistre une mesure retenue par la règle, et rend ce qui a été écrit.
  ///
  /// Passé en fonction plutôt qu'en dépendance sur le contrôleur d'historique :
  /// c'est ce qui permet de tester la règle d'échantillonnage sans base.
  final Future<WaterReading?> Function(WaterReading) _onSample;

  /// Dernière mesure de sonde déjà enregistrée, référence de la règle.
  final Future<WaterReading?> Function() _lastSensorReading;

  final DateTime Function() _clock;

  StreamSubscription<PoolTelemetry>? _telemetrySubscription;
  StreamSubscription<bool>? _onlineSubscription;

  /// Dernière mesure retenue, gardée en mémoire pour ne pas interroger la base
  /// à chaque trame — soit 43 200 requêtes par jour.
  WaterReading? _lastRecorded;
  bool _referenceLoaded = false;

  /// Nombre de trames reçues, pour le diagnostic.
  int framesReceived = 0;

  /// Nombre de mesures effectivement entrées dans l'historique.
  int samplesRecorded = 0;

  /// Ouvre la liaison et commence à suivre la télémétrie.
  Future<void> start() async {
    final WokwiMqttDriver? driver = _driver;
    if (driver == null) {
      return;
    }
    _telemetrySubscription ??= driver.telemetryStream.listen(_handleFrame);
    _onlineSubscription ??= driver.moduleOnlineStream.listen(_handleOnline);
    try {
      await driver.start();
      state = state.copyWith(clearError: true);
    } on DeviceException catch (error) {
      // Une liaison qui ne s'ouvre pas n'empêche ni la saisie manuelle ni le
      // calcul des doses : on l'affiche et on continue.
      state = state.copyWith(
        isModuleOnline: false,
        isFresh: false,
        errorMessage: error.message,
      );
    }
  }

  void _handleOnline(bool online) {
    state = state.copyWith(
      isModuleOnline: online,
      // Un module qui passe hors ligne rend sa dernière trame non
      // représentative, quel que soit son âge.
      isFresh: online ? state.isFresh : false,
    );
  }

  void _handleFrame(PoolTelemetry telemetry) {
    framesReceived++;
    state = state.copyWith(
      telemetry: telemetry,
      isModuleOnline: true,
      isFresh: true,
      filterAlert: telemetry.filterAlert,
      clearError: true,
    );
    unawaited(_maybeRecord(telemetry));
  }

  /// Applique la règle d'échantillonnage à une trame.
  Future<void> _maybeRecord(PoolTelemetry telemetry) async {
    if (!_referenceLoaded) {
      // Première trame de la session : la référence vient de la base, pour
      // que le rythme d'une heure survive à un redémarrage de l'application.
      _lastRecorded = await _lastSensorReading();
      _referenceLoaded = true;
    }

    final WaterReading? candidate = ReadingSampler.sample(
      at: _clock(),
      lastRecorded: _lastRecorded,
      ph: telemetry.ph,
      temperatureC: telemetry.temperatureC,
    );
    if (candidate == null) {
      return;
    }

    final WaterReading? recorded = await _onSample(candidate);
    if (recorded != null) {
      // La référence n'avance que si l'écriture a réussi : sinon le prochain
      // point serait comparé à une mesure qui n'existe pas en base.
      _lastRecorded = recorded;
      samplesRecorded++;
    }
  }

  /// Vérifie la liaison et rend la latence, ou lève une [DeviceException].
  Future<Duration> testConnection() async {
    final WokwiMqttDriver? driver = _driver;
    if (driver == null) {
      throw const DeviceException(
        'Aucune liaison MQTT n’est configurée. Choisissez ce type de liaison '
        'dans les réglages pour la tester.',
        technicalDetail: 'telemetryController sans pilote MQTT',
      );
    }
    try {
      final Duration latency = await driver.ping();
      state = state.copyWith(clearError: true);
      return latency;
    } on DeviceException catch (error) {
      state = state.copyWith(errorMessage: error.message);
      rethrow;
    }
  }

  /// Réévalue la fraîcheur de la dernière trame.
  ///
  /// Appelé par l'écran à intervalle régulier : sans nouvelle trame, l'état
  /// affiché doit finir par se déclarer périmé plutôt que de rester figé sur
  /// une valeur d'il y a dix minutes.
  void refreshFreshness() {
    state = state.copyWith(isFresh: _driver?.hasFreshTelemetry ?? false);
  }

  /// Libère les abonnements, et RIEN d'autre.
  ///
  /// Le pilote n'est pas libéré ici : il est injecté, donc il appartient à son
  /// provider, qui le referme quand la configuration change de type de
  /// liaison. Le libérer des deux côtés fermerait le transport sous les pieds
  /// d'un contrôleur encore vivant.
  @override
  void dispose() {
    unawaited(_telemetrySubscription?.cancel());
    unawaited(_onlineSubscription?.cancel());
    _telemetrySubscription = null;
    _onlineSubscription = null;
    super.dispose();
  }
}
