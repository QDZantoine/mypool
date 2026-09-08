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

/// La mesure de référence pour les recommandations.
///
/// La base est la dernière SAISIE de l'utilisateur, et non la mesure la plus
/// récente : la sonde s'enregistre toute seule et serait presque toujours la
/// plus récente, ce qui masquerait la bandelette qu'on vient de lire. Une
/// sonde ne mesure d'ailleurs ni le TAC, ni le TH, ni le stabilisant, dont
/// dépendent la plupart des doses.
///
/// La télémétrie ne complète que ce que la saisie ne dit pas.
final Provider<WaterReading?> effectiveReadingProvider =
    Provider<WaterReading?>((Ref ref) {
      final WaterReading? recorded = ref.watch(
        readingsProvider.select((ReadingsState s) => s.latestManual),
      );
      final TelemetryState telemetry = ref.watch(telemetryProvider);

      if (!telemetry.hasLiveValues) {
        return recorded;
      }
      if (recorded == null) {
        // Rien de saisi : on affiche ce que la sonde dit, marqué comme tel.
        return WaterReading(
          takenAt: telemetry.telemetry!.receivedAt,
          ph: telemetry.livePh,
          temperature: telemetry.liveTemperatureC,
          source: MeasurementSource.sensor,
        );
      }
      // Les valeurs de sonde ne remplacent que ce qui manque à la saisie.
      return recorded.copyWith(
        ph: recorded.ph ?? telemetry.livePh,
        temperature: recorded.temperature ?? telemetry.liveTemperatureC,
      );
    });

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
/// La sonde passe devant la saisie ici, contrairement aux recommandations : la
/// durée de filtration suit la température du jour, et une mesure d'il y a
/// trois jours ne la décrit plus.
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
