import 'chemical_product.dart';
import 'json_tolerant.dart';

/// Mode de traitement de l'eau déclaré par l'utilisateur.
///
/// Il determine quel produit chlore est propose et si la règle du stabilisant
/// s'applique : un bassin traité à l'oxygène actif n'a pas de chlore à doser.
enum TreatmentType {
  /// Chlore stabilisé (galets de trichlor) : le stabilisant s'accumule.
  stabilizedChlorine,

  /// Chlore non stabilisé (hypochlorite) : pas d'accumulation d'acide
  /// cyanurique, mais une consommation UV bien plus rapide.
  unstabilizedChlorine,

  /// Électrolyse au sel : le chlore est produit en continu par la cellule.
  salt,

  /// Brome : pas de stabilisant, plage de pH plus large.
  bromine,

  /// Oxygène actif : aucun dosage de chlore.
  activeOxygen,
}

/// Type de filtre. Il fixe la finesse de filtration et donc la durée utile.
enum FilterType { sand, glass, cartridge, diatomaceousEarth, zeolite }

/// Type de couverture. Un volet immergé ou hors-sol est un dispositif de
/// sécurité au sens de la norme NF P90-308 ; une simple bâche ne l'est pas.
enum CoverType {
  /// Volet roulant immergé (axe sous l'eau).
  submerged,

  /// Volet roulant hors d'eau (axe sur la margelle).
  outOfWater,

  /// Couverture à barres.
  bars,

  /// Bâche à bulles : isolation thermique seule, aucune fonction de sécurité.
  bubbleCover,

  /// Aucune couverture.
  none,
}

/// Genre de pilote matériel utilisé pour parler au bassin.
///
/// Toute la variabilite matérielle est derriere `PoolDeviceDriver` ; ce genre
/// dit seulement quelle implementation instancier.
enum DriverKind {
  /// Simulation locale : aucun accès réseau. Valeur par défaut, pour que
  /// l'application soit utilisable avant tout appairage.
  simulation,

  /// Module local piloté en RPC (Shelly).
  localModule,

  /// Passerelle Home Assistant.
  homeAssistant,

  /// Carte ESP32 en MQTT : banc d'essai Wokwi, et toute future carte
  /// (addendum § 1.1). Ajoutée en fin d'énumération pour ne pas décaler les
  /// index des valeurs déjà écrites sur le disque.
  mqtt,
}

/// Nom court du paragraphe 8.1 du cahier des charges, conserve comme alias.
typedef Kind = DriverKind;

/// Configuration du bassin. Immuable : toute modification passe par copyWith.
class PoolConfig {
  const PoolConfig({
    this.name = defaultName,
    this.volumeM3 = defaultVolumeM3,
    this.lengthM = defaultLengthM,
    this.widthM = defaultWidthM,
    this.averageDepthM = defaultAverageDepthM,
    this.treatment = TreatmentType.stabilizedChlorine,
    this.filter = FilterType.sand,
    this.cover = CoverType.submerged,
    this.pumpFlowM3PerHour = defaultPumpFlowM3PerHour,
    this.pumpEfficiency = defaultPumpEfficiency,
    this.coverTravelSeconds = defaultCoverTravelSeconds,
    this.driver = DriverKind.simulation,
    this.inventory = ChemicalInventory.standard,
    this.safetyConsentGiven = false,
  });

  // --- Valeurs par défaut : une piscine 8 x 4 m immédiatement utilisable. ---

  static const String defaultName = 'Ma piscine';

  /// 8 m x 4 m x 1,25 m de profondeur moyenne = 40 m3.
  static const double defaultVolumeM3 = 40.0;
  static const double defaultLengthM = 8.0;
  static const double defaultWidthM = 4.0;
  static const double defaultAverageDepthM = 1.25;

  /// Débit nominal de la pompe, en m3/h (plaque constructeur).
  static const double defaultPumpFlowM3PerHour = 10.0;

  /// Rendement hydraulique réel : pertes de charge, encrassement du filtre et
  /// des paniers. Le débit utile est donc 10 x 0,75 = 7,5 m3/h.
  static const double defaultPumpEfficiency = 0.75;

  /// Durée d'une course complète du volet, en secondes (mesurée au chronomètre).
  static const double defaultCoverTravelSeconds = 90.0;

  final String name;

  /// Volume d'eau en m3. Source de verite du calcul de dose : l'utilisateur
  /// peut le saisir directement quand le bassin n'est pas rectangulaire.
  final double volumeM3;

  final double lengthM;
  final double widthM;
  final double averageDepthM;

  final TreatmentType treatment;
  final FilterType filter;
  final CoverType cover;

  final double pumpFlowM3PerHour;

  /// Rendement de la pompe, entre 0 et 1.
  final double pumpEfficiency;

  final double coverTravelSeconds;

  final DriverKind driver;

  /// Produits déclarés, avec leurs concentrations.
  final ChemicalInventory inventory;

  /// Consentement à l'avertissement de sécurité du volet. Sans lui, aucune
  /// commande de volet n'agit (règle de sécurité n. 4).
  final bool safetyConsentGiven;

  /// Volume déduit des dimensions, pour proposer une valeur à la saisie.
  double get volumeFromDimensions => lengthM * widthM * averageDepthM;

  /// Débit réellement disponible pour le calcul de rotation, en m3/h.
  double get effectiveFlowM3PerHour => pumpFlowM3PerHour * pumpEfficiency;

  /// Le stabilisant ne s'accumule qu'avec du chlore stabilisé ; c'est le seul
  /// cas ou la règle des 7,5 % et le renouvellement d'eau ont un sens.
  bool get usesStabilizedChlorine =>
      treatment == TreatmentType.stabilizedChlorine;

  /// Un bassin traité au brome ou à l'oxygène actif n'a pas de chlore à doser.
  bool get usesChlorine =>
      treatment == TreatmentType.stabilizedChlorine ||
      treatment == TreatmentType.unstabilizedChlorine ||
      treatment == TreatmentType.salt;

  /// Le volet est un dispositif de sécurité pour les deux types de volets
  /// roulants ; les baches et les couvertures à barres ne se pilotent pas.
  bool get hasMotorisedCover =>
      cover == CoverType.submerged || cover == CoverType.outOfWater;

  PoolConfig copyWith({
    String? name,
    double? volumeM3,
    double? lengthM,
    double? widthM,
    double? averageDepthM,
    TreatmentType? treatment,
    FilterType? filter,
    CoverType? cover,
    double? pumpFlowM3PerHour,
    double? pumpEfficiency,
    double? coverTravelSeconds,
    DriverKind? driver,
    ChemicalInventory? inventory,
    bool? safetyConsentGiven,
  }) {
    return PoolConfig(
      name: name ?? this.name,
      volumeM3: volumeM3 ?? this.volumeM3,
      lengthM: lengthM ?? this.lengthM,
      widthM: widthM ?? this.widthM,
      averageDepthM: averageDepthM ?? this.averageDepthM,
      treatment: treatment ?? this.treatment,
      filter: filter ?? this.filter,
      cover: cover ?? this.cover,
      pumpFlowM3PerHour: pumpFlowM3PerHour ?? this.pumpFlowM3PerHour,
      pumpEfficiency: pumpEfficiency ?? this.pumpEfficiency,
      coverTravelSeconds: coverTravelSeconds ?? this.coverTravelSeconds,
      driver: driver ?? this.driver,
      inventory: inventory ?? this.inventory,
      safetyConsentGiven: safetyConsentGiven ?? this.safetyConsentGiven,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'volumeM3': volumeM3,
      'lengthM': lengthM,
      'widthM': widthM,
      'averageDepthM': averageDepthM,
      'treatment': treatment.name,
      'filter': filter.name,
      'cover': cover.name,
      'pumpFlowM3PerHour': pumpFlowM3PerHour,
      'pumpEfficiency': pumpEfficiency,
      'coverTravelSeconds': coverTravelSeconds,
      'driver': driver.name,
      'inventory': inventory.toJson(),
      'safetyConsentGiven': safetyConsentGiven,
    };
  }

  /// Reconstruit la configuration. Chaque champ est borne à une plage
  /// physiquement plausible : c'est ce qui empeche une préférence corrompue de
  /// produire une dose absurde plutôt qu'un écran d'erreur.
  factory PoolConfig.fromJson(Object? raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return PoolConfig(
      name: readString(json, 'name', defaultName),
      // 1 à 1 000 m3 : de la mini-piscine au bassin collectif.
      volumeM3: clampDouble(
        readDouble(json, 'volumeM3', defaultVolumeM3),
        1.0,
        1000.0,
      ),
      lengthM: clampDouble(
        readDouble(json, 'lengthM', defaultLengthM),
        0.5,
        100.0,
      ),
      widthM: clampDouble(
        readDouble(json, 'widthM', defaultWidthM),
        0.5,
        100.0,
      ),
      averageDepthM: clampDouble(
        readDouble(json, 'averageDepthM', defaultAverageDepthM),
        0.2,
        5.0,
      ),
      treatment: readEnum(
        json,
        'treatment',
        TreatmentType.values,
        TreatmentType.stabilizedChlorine,
      ),
      filter: readEnum(json, 'filter', FilterType.values, FilterType.sand),
      cover: readEnum(json, 'cover', CoverType.values, CoverType.submerged),
      // 0,5 à 100 m3/h couvre les pompes domestiques et semi-collectives.
      pumpFlowM3PerHour: clampDouble(
        readDouble(json, 'pumpFlowM3PerHour', defaultPumpFlowM3PerHour),
        0.5,
        100.0,
      ),
      // Un rendement au-delà de 1 n'a pas de sens physique ; sous 0,1 la
      // rotation calculée depasserait la journée.
      pumpEfficiency: clampDouble(
        readDouble(json, 'pumpEfficiency', defaultPumpEfficiency),
        0.1,
        1.0,
      ),
      // 5 s à 600 s : de la petite piscine au bassin de 15 m.
      coverTravelSeconds: clampDouble(
        readDouble(json, 'coverTravelSeconds', defaultCoverTravelSeconds),
        5.0,
        600.0,
      ),
      driver: readEnum(
        json,
        'driver',
        DriverKind.values,
        DriverKind.simulation,
      ),
      inventory: ChemicalInventory.fromJson(json['inventory']),
      // Le consentement de sécurité ne se devine pas : tout ce qui n'est pas
      // un `true` explicite vaut « non consenti ».
      safetyConsentGiven: readBool(json, 'safetyConsentGiven', false),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PoolConfig &&
        other.name == name &&
        other.volumeM3 == volumeM3 &&
        other.lengthM == lengthM &&
        other.widthM == widthM &&
        other.averageDepthM == averageDepthM &&
        other.treatment == treatment &&
        other.filter == filter &&
        other.cover == cover &&
        other.pumpFlowM3PerHour == pumpFlowM3PerHour &&
        other.pumpEfficiency == pumpEfficiency &&
        other.coverTravelSeconds == coverTravelSeconds &&
        other.driver == driver &&
        other.inventory == inventory &&
        other.safetyConsentGiven == safetyConsentGiven;
  }

  @override
  int get hashCode => Object.hash(
    name,
    volumeM3,
    lengthM,
    widthM,
    averageDepthM,
    treatment,
    filter,
    cover,
    pumpFlowM3PerHour,
    pumpEfficiency,
    coverTravelSeconds,
    driver,
    inventory,
    safetyConsentGiven,
  );

  @override
  String toString() => 'PoolConfig($name, ${volumeM3}m3, ${treatment.name})';
}
