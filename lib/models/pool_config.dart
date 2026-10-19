import 'chemical_product.dart';
import 'json_tolerant.dart';

enum TreatmentType {

  stabilizedChlorine,

  unstabilizedChlorine,

  salt,

  bromine,

  activeOxygen,
}

enum FilterType { sand, glass, cartridge, diatomaceousEarth, zeolite }

enum CoverType {

  submerged,

  outOfWater,

  bars,

  bubbleCover,

  none,
}

enum DriverKind {

  simulation,

  localModule,

  homeAssistant,

  mqtt,
}

typedef Kind = DriverKind;

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

  static const String defaultName = 'Ma piscine';

  static const double defaultVolumeM3 = 40.0;
  static const double defaultLengthM = 8.0;
  static const double defaultWidthM = 4.0;
  static const double defaultAverageDepthM = 1.25;

  static const double defaultPumpFlowM3PerHour = 10.0;

  static const double defaultPumpEfficiency = 0.75;

  static const double defaultCoverTravelSeconds = 90.0;

  final String name;

  final double volumeM3;

  final double lengthM;
  final double widthM;
  final double averageDepthM;

  final TreatmentType treatment;
  final FilterType filter;
  final CoverType cover;

  final double pumpFlowM3PerHour;

  final double pumpEfficiency;

  final double coverTravelSeconds;

  final DriverKind driver;

  final ChemicalInventory inventory;

  final bool safetyConsentGiven;

  double get volumeFromDimensions => lengthM * widthM * averageDepthM;

  double get effectiveFlowM3PerHour => pumpFlowM3PerHour * pumpEfficiency;

  bool get usesStabilizedChlorine =>
      treatment == TreatmentType.stabilizedChlorine;

  bool get usesChlorine =>
      treatment == TreatmentType.stabilizedChlorine ||
      treatment == TreatmentType.unstabilizedChlorine ||
      treatment == TreatmentType.salt;

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

  factory PoolConfig.fromJson(Object? raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return PoolConfig(
      name: readString(json, 'name', defaultName),

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

      pumpFlowM3PerHour: clampDouble(
        readDouble(json, 'pumpFlowM3PerHour', defaultPumpFlowM3PerHour),
        0.5,
        100.0,
      ),

      pumpEfficiency: clampDouble(
        readDouble(json, 'pumpEfficiency', defaultPumpEfficiency),
        0.1,
        1.0,
      ),

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
