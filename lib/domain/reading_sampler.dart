import '../models/water_reading.dart';
import 'chemistry_engine.dart';

class ReadingSampler {

  static const Duration minimumInterval = Duration(hours: 1);

  static const double phDelta = 0.1;

  static const double temperatureDelta = 0.5;

  static WaterReading? sample({
    required DateTime at,
    required WaterReading? lastRecorded,
    double? ph,
    double? temperatureC,
  }) {
    if (ph == null && temperatureC == null) {

      return null;
    }

    final WaterReading candidate = WaterReading(
      takenAt: at,
      ph: ph,
      temperature: temperatureC,
      source: MeasurementSource.sensor,
    );

    if (lastRecorded == null) {

      return candidate;
    }

    if (at.difference(lastRecorded.takenAt) < minimumInterval) {
      return null;
    }

    return hasMoved(
          ph: ph,
          temperatureC: temperatureC,
          lastRecorded: lastRecorded,
        )
        ? candidate
        : null;
  }

  static bool hasMoved({
    required WaterReading lastRecorded,
    double? ph,
    double? temperatureC,
  }) {
    if (_movedBy(ph, lastRecorded.ph, phDelta)) {
      return true;
    }
    return _movedBy(temperatureC, lastRecorded.temperature, temperatureDelta);
  }

  static bool _movedBy(double? current, double? previous, double threshold) {
    if (current == null) {
      return false;
    }
    if (previous == null) {

      return true;
    }

    final double gap = ChemistryEngine.roundGap(current - previous).abs();
    return gap >= threshold;
  }
}
