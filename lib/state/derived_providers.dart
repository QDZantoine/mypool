import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/chemistry_engine.dart';
import '../domain/filtration_planner.dart';
import '../domain/water_balance.dart';
import '../models/dose_recommendation.dart';
import '../models/filtration_schedule.dart';
import '../models/pool_config.dart';
import '../models/water_reading.dart';
import 'providers.dart';
import 'telemetry_controller.dart';
import 'water_readings_controller.dart';

/// Vues dérivées de l'état, calculées par les moteurs de `domain/`.
///
/// Aucun de ces providers ne contient de formule : ils assemblent les entrées
/// et appellent un moteur pur. C'est ce qui permet de vérifier les calculs
/// sans Riverpod, et de vérifier le câblage sans refaire les calculs.

/// Les paramètres qu'une sonde mesure en continu.
///
/// La liste est courte, et c'est une réalité du matériel : le montage remonte
/// un pH et une température, rien de plus. Il n'existe pas de sonde
/// domestique de TAC, de TH ni de stabilisant — ces valeurs se lisent à la
/// bandelette. Le chlore se sonde (redox), mais pas sur ce montage.
///
/// L'interface s'appuie sur cette liste pour dire à l'utilisateur ce qui est
/// suivi tout seul et ce qu'il doit encore tester lui-même.
const List<WaterParameter> sensorParameters = <WaterParameter>[
  WaterParameter.ph,
  WaterParameter.temperature,
];

/// Les paramètres qui ne se mesurent qu'à la main.
final Provider<List<WaterParameter>> manualParametersProvider =
    Provider<List<WaterParameter>>((Ref ref) {
      final PoolConfig config = ref.watch(poolConfigProvider);
      return <WaterParameter>[
        if (config.usesChlorine) WaterParameter.freeChlorine,
        if (config.usesChlorine) WaterParameter.combinedChlorine,
        WaterParameter.tac,
        WaterParameter.th,
        if (config.usesChlorine) WaterParameter.stabilizer,
        if (config.treatment == TreatmentType.salt) WaterParameter.salt,
      ];
    });

/// La mesure de référence pour les recommandations.
///
/// LA SONDE FAIT FOI pour ce qu'elle mesure. Une lecture de sonde de deux
/// secondes décrit l'eau telle qu'elle est maintenant ; une bandelette lue
/// dimanche dernier décrit l'eau de dimanche dernier. Doser un pH sur une
/// valeur de la semaine passée fait verser à côté.
///
/// La saisie apporte tout le reste — TAC, TH, stabilisant, chlore, sel — que
/// nulle sonde de ce montage ne mesure, et sans quoi le moteur de dosage n'a
/// pas ses entrées : c'est le TAC qui fixe la dose de pH et le stabilisant qui
/// fixe la cible de chlore.
///
/// Quand la sonde est hors ligne ou sa trame périmée, la saisie reprend la
/// main : mieux vaut une valeur datée dont on connaît l'âge qu'aucune valeur.
final Provider<WaterReading?> effectiveReadingProvider =
    Provider<WaterReading?>((Ref ref) {
      final WaterReading? entered = ref.watch(
        readingsProvider.select((ReadingsState s) => s.latestManual),
      );
      final TelemetryState telemetry = ref.watch(telemetryProvider);

      if (!telemetry.hasLiveValues) {
        return entered;
      }
      final double? livePh = telemetry.livePh;
      final double? liveTemperature = telemetry.liveTemperatureC;

      if (entered == null) {
        // Rien de saisi : on travaille avec ce que la sonde donne, marqué
        // comme venant d'elle.
        return WaterReading(
          takenAt: telemetry.telemetry!.receivedAt,
          ph: livePh,
          temperature: liveTemperature,
          source: MeasurementSource.sensor,
        );
      }

      // La sonde ÉCRASE le pH et la température saisis : ils décrivent l'eau
      // maintenant. `copyWith` ne sait pas remettre une valeur à null, d'où la
      // reconstruction explicite.
      return WaterReading(
        takenAt: telemetry.telemetry!.receivedAt,
        ph: livePh ?? entered.ph,
        temperature: liveTemperature ?? entered.temperature,
        freeChlorine: entered.freeChlorine,
        combinedChlorine: entered.combinedChlorine,
        tac: entered.tac,
        th: entered.th,
        stabilizer: entered.stabilizer,
        salt: entered.salt,
        note: entered.note,
        source: MeasurementSource.sensor,
      );
    });

/// La dernière saisie, telle quelle, pour afficher son âge.
final Provider<WaterReading?> lastEnteredReadingProvider =
    Provider<WaterReading?>(
      (Ref ref) => ref.watch(
        readingsProvider.select((ReadingsState s) => s.latestManual),
      ),
    );

/// Les actions à mener, dans l'ordre métier (annexe A.2 à A.5).
///
/// Vide sans mesure : proposer une dose sans savoir où en est l'eau serait
/// deviner.
final Provider<List<DoseRecommendation>> recommendationsProvider =
    Provider<List<DoseRecommendation>>((Ref ref) {
      final WaterReading? reading = ref.watch(effectiveReadingProvider);
      if (reading == null) {
        return const <DoseRecommendation>[];
      }
      return ChemistryEngine.recommend(
        config: ref.watch(poolConfigProvider),
        reading: reading,
      );
    });

/// Équilibre calco-carbonique (annexe A.6), ou `null` s'il manque une donnée.
final Provider<WaterBalanceResult?> waterBalanceProvider =
    Provider<WaterBalanceResult?>((Ref ref) {
      final WaterReading? reading = ref.watch(effectiveReadingProvider);
      if (reading == null) {
        return null;
      }
      return WaterBalance.fromReading(reading);
    });

/// Température de l'eau retenue pour la filtration.
///
/// Même règle que partout : la sonde d'abord, la saisie en secours.
final Provider<double?> waterTemperatureProvider = Provider<double?>((Ref ref) {
  final TelemetryState telemetry = ref.watch(telemetryProvider);
  final double? live = telemetry.liveTemperatureC;
  if (live != null) {
    return live;
  }
  // Toutes origines confondues ici : pour la filtration, une température de
  // sonde vaut une température saisie, seule sa fraîcheur compte.
  return ref.watch(
    readingsProvider.select((ReadingsState s) => s.latest?.temperature),
  );
});

/// Planning de filtration recommandé (annexe A.7), ou `null` sans
/// température.
///
/// Le `null` est volontaire : sans température, la règle « moitié de la
/// température » n'a rien à calculer, et proposer un planning par défaut
/// ferait filtrer treize heures un bassin à 12 °C.
final Provider<FiltrationSchedule?> filtrationPlanProvider =
    Provider<FiltrationSchedule?>((Ref ref) {
      final double? temperature = ref.watch(waterTemperatureProvider);
      if (temperature == null) {
        return null;
      }
      return FiltrationPlanner.plan(
        config: ref.watch(poolConfigProvider),
        temperatureC: temperature,
      );
    });

/// Durée d'une rotation complète du volume, toujours calculable.
///
/// Elle ne dépend que du bassin et de la pompe, pas de la température : c'est
/// pourquoi elle reste affichable même sans mesure.
final Provider<Duration> turnoverProvider = Provider<Duration>((Ref ref) {
  final PoolConfig config = ref.watch(poolConfigProvider);
  return FiltrationPlanner.turnoverTime(
    volumeM3: config.volumeM3,
    flowM3PerHour: config.pumpFlowM3PerHour,
    efficiency: config.pumpEfficiency,
  );
});

/// L'action la plus urgente, pour l'accueil.
///
/// L'utilisateur est debout au bord du bassin, une main occupée : la première
/// chose qu'il voit doit être ce qu'il y a à faire maintenant.
final Provider<DoseRecommendation?> nextActionProvider =
    Provider<DoseRecommendation?>((Ref ref) {
      final List<DoseRecommendation> actions = ref.watch(
        recommendationsProvider,
      );
      return actions.isEmpty ? null : actions.first;
    });
