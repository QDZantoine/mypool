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

const List<WaterParameter> sensorParameters = <WaterParameter>[
  WaterParameter.ph,
  WaterParameter.temperature,
];

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

        return WaterReading(
          takenAt: telemetry.telemetry!.receivedAt,
          ph: livePh,
          temperature: liveTemperature,
          source: MeasurementSource.sensor,
        );
      }

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

final Provider<WaterReading?> lastEnteredReadingProvider =
    Provider<WaterReading?>(
      (Ref ref) => ref.watch(
        readingsProvider.select((ReadingsState s) => s.latestManual),
      ),
    );

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

final Provider<WaterBalanceResult?> waterBalanceProvider =
    Provider<WaterBalanceResult?>((Ref ref) {
      final WaterReading? reading = ref.watch(effectiveReadingProvider);
      if (reading == null) {
        return null;
      }
      return WaterBalance.fromReading(reading);
    });

final Provider<double?> waterTemperatureProvider = Provider<double?>((Ref ref) {
  final TelemetryState telemetry = ref.watch(telemetryProvider);
  final double? live = telemetry.liveTemperatureC;
  if (live != null) {
    return live;
  }

  return ref.watch(
    readingsProvider.select((ReadingsState s) => s.latest?.temperature),
  );
});

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

final Provider<Duration> turnoverProvider = Provider<Duration>((Ref ref) {
  final PoolConfig config = ref.watch(poolConfigProvider);
  return FiltrationPlanner.turnoverTime(
    volumeM3: config.volumeM3,
    flowM3PerHour: config.pumpFlowM3PerHour,
    efficiency: config.pumpEfficiency,
  );
});

final Provider<DoseRecommendation?> nextActionProvider =
    Provider<DoseRecommendation?>((Ref ref) {
      final List<DoseRecommendation> actions = ref.watch(
        recommendationsProvider,
      );
      return actions.isEmpty ? null : actions.first;
    });
