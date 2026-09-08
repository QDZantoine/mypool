import '../models/water_reading.dart';
import 'chemistry_engine.dart';

/// Échantillonnage des mesures automatiques (addendum § 5).
///
/// PUR : aucun import Flutter, aucun accès disque ou réseau, aucune lecture de
/// l'horloge. La conversion d'une trame de télémétrie en valeurs se fait au
/// niveau au-dessus : `domain/` ne connaît pas `data/`.
///
/// Le problème résolu : le module publie une mesure toutes les 2 s, soit
/// 43 200 lignes par jour. Les enregistrer toutes noierait un historique dont
/// l'intérêt est de montrer une dérive sur trois jours. La règle retenue ne
/// garde donc une mesure que si elle apprend quelque chose.
class ReadingSampler {
  /// Intervalle minimal entre deux enregistrements automatiques.
  ///
  /// Une heure : le pH d'un bassin bouge en jours, pas en minutes. C'est déjà
  /// vingt-quatre points par jour, plus que ce qu'une courbe peut montrer.
  static const Duration minimumInterval = Duration(hours: 1);

  /// Variation de pH à partir de laquelle la mesure devient intéressante.
  ///
  /// 0,1 unité est aussi la résolution d'un testeur : en dessous, la variation
  /// n'est pas distinguable du bruit de la sonde.
  static const double phDelta = 0.1;

  /// Variation de température à partir de laquelle la mesure devient
  /// intéressante, en °C.
  ///
  /// 0,5 °C : c'est le pas qui change une durée de filtration d'un quart
  /// d'heure environ, donc le premier écart qui a une conséquence visible.
  static const double temperatureDelta = 0.5;

  /// Décide si une mesure de sonde mérite d'entrer dans l'historique, et la
  /// construit le cas échéant.
  ///
  /// Rend `null` quand il n'y a rien à enregistrer. La mesure produite est
  /// marquée [MeasurementSource.sensor] : une sonde non calibrée et une
  /// bandelette ne se valent pas, et l'historique doit permettre de les
  /// distinguer.
  static WaterReading? sample({
    required DateTime at,
    required WaterReading? lastRecorded,
    double? ph,
    double? temperatureC,
  }) {
    if (ph == null && temperatureC == null) {
      // Une trame sans mesure exploitable n'a rien à apporter.
      return null;
    }

    final WaterReading candidate = WaterReading(
      takenAt: at,
      ph: ph,
      temperature: temperatureC,
      source: MeasurementSource.sensor,
    );

    if (lastRecorded == null) {
      // Premier point de l'historique : il n'y a rien à comparer, et une
      // courbe vide n'aide personne.
      return candidate;
    }

    // Le rythme passe avant la variation : même une grosse dérive n'a pas
    // besoin de deux points à cinq minutes d'intervalle.
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

  /// Une des valeurs a-t-elle bougé assez pour valoir un enregistrement ?
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
      // La mesure précédente ne portait pas cette valeur : la connaître est
      // en soi une information nouvelle.
      return true;
    }
    // Écart arrondi au centième AVANT la comparaison, pour la même raison que
    // dans l'annexe A.2 : 7,3 - 7,2 vaut 0,09999999999999964 en virgule
    // flottante, ce qui ferait rejeter une variation qui atteint pourtant
    // exactement le seuil.
    final double gap = ChemistryEngine.roundGap(current - previous).abs();
    return gap >= threshold;
  }
}
