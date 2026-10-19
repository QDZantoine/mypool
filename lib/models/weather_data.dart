import 'json_tolerant.dart';

class WeatherLocation {
  const WeatherLocation({
    this.name = '',
    this.region = '',
    this.country = '',
    this.lat = 0.0,
    this.lon = 0.0,
    this.tzId = '',
    this.localtimeEpoch = 0,
    this.localtime = '',
  });

  final String name;
  final String region;
  final String country;
  final double lat;
  final double lon;
  final String tzId;
  final int localtimeEpoch;
  final String localtime;

  factory WeatherLocation.fromJson(Object? raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return WeatherLocation(
      name: readString(json, 'name', ''),
      region: readString(json, 'region', ''),
      country: readString(json, 'country', ''),
      lat: readDouble(json, 'lat', 0.0),
      lon: readDouble(json, 'lon', 0.0),
      tzId: readString(json, 'tz_id', ''),
      localtimeEpoch: readInt(json, 'localtime_epoch', 0),
      localtime: readString(json, 'localtime', ''),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'region': region,
      'country': country,
      'lat': lat,
      'lon': lon,
      'tz_id': tzId,
      'localtime_epoch': localtimeEpoch,
      'localtime': localtime,
    };
  }

  WeatherLocation copyWith({
    String? name,
    String? region,
    String? country,
    double? lat,
    double? lon,
    String? tzId,
    int? localtimeEpoch,
    String? localtime,
  }) {
    return WeatherLocation(
      name: name ?? this.name,
      region: region ?? this.region,
      country: country ?? this.country,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      tzId: tzId ?? this.tzId,
      localtimeEpoch: localtimeEpoch ?? this.localtimeEpoch,
      localtime: localtime ?? this.localtime,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WeatherLocation &&
        other.name == name &&
        other.region == region &&
        other.country == country &&
        other.lat == lat &&
        other.lon == lon &&
        other.tzId == tzId &&
        other.localtimeEpoch == localtimeEpoch &&
        other.localtime == localtime;
  }

  @override
  int get hashCode => Object.hash(
        name,
        region,
        country,
        lat,
        lon,
        tzId,
        localtimeEpoch,
        localtime,
      );

  @override
  String toString() => 'WeatherLocation($name, $country, $lat, $lon)';
}

class WeatherCondition {
  const WeatherCondition({
    this.text = '',
    this.icon = '',
    this.code = 0,
  });

  final String text;
  final String icon;
  final int code;

  factory WeatherCondition.fromJson(Object? raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return WeatherCondition(
      text: readString(json, 'text', ''),
      icon: readString(json, 'icon', ''),
      code: readInt(json, 'code', 0),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'text': text,
      'icon': icon,
      'code': code,
    };
  }

  WeatherCondition copyWith({
    String? text,
    String? icon,
    int? code,
  }) {
    return WeatherCondition(
      text: text ?? this.text,
      icon: icon ?? this.icon,
      code: code ?? this.code,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WeatherCondition &&
        other.text == text &&
        other.icon == icon &&
        other.code == code;
  }

  @override
  int get hashCode => Object.hash(text, icon, code);

  @override
  String toString() => 'WeatherCondition($text, code: $code)';
}

class AirQuality {
  const AirQuality({
    this.co,
    this.no2,
    this.o3,
    this.so2,
    this.pm25,
    this.pm10,
    this.usEpaIndex,
    this.gbDefraIndex,
  });

  final double? co;
  final double? no2;
  final double? o3;
  final double? so2;
  final double? pm25;
  final double? pm10;
  final int? usEpaIndex;
  final int? gbDefraIndex;

  factory AirQuality.fromJson(Object? raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return AirQuality(
      co: readNullableDouble(json, 'co'),
      no2: readNullableDouble(json, 'no2'),
      o3: readNullableDouble(json, 'o3'),
      so2: readNullableDouble(json, 'so2'),
      pm25: readNullableDouble(json, 'pm2_5'),
      pm10: readNullableDouble(json, 'pm10'),
      usEpaIndex: json.containsKey('us-epa-index')
          ? readInt(json, 'us-epa-index', 0)
          : null,
      gbDefraIndex: json.containsKey('gb-defra-index')
          ? readInt(json, 'gb-defra-index', 0)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (co != null) 'co': co,
      if (no2 != null) 'no2': no2,
      if (o3 != null) 'o3': o3,
      if (so2 != null) 'so2': so2,
      if (pm25 != null) 'pm2_5': pm25,
      if (pm10 != null) 'pm10': pm10,
      if (usEpaIndex != null) 'us-epa-index': usEpaIndex,
      if (gbDefraIndex != null) 'gb-defra-index': gbDefraIndex,
    };
  }

  AirQuality copyWith({
    double? co,
    double? no2,
    double? o3,
    double? so2,
    double? pm25,
    double? pm10,
    int? usEpaIndex,
    int? gbDefraIndex,
  }) {
    return AirQuality(
      co: co ?? this.co,
      no2: no2 ?? this.no2,
      o3: o3 ?? this.o3,
      so2: so2 ?? this.so2,
      pm25: pm25 ?? this.pm25,
      pm10: pm10 ?? this.pm10,
      usEpaIndex: usEpaIndex ?? this.usEpaIndex,
      gbDefraIndex: gbDefraIndex ?? this.gbDefraIndex,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AirQuality &&
        other.co == co &&
        other.no2 == no2 &&
        other.o3 == o3 &&
        other.so2 == so2 &&
        other.pm25 == pm25 &&
        other.pm10 == pm10 &&
        other.usEpaIndex == usEpaIndex &&
        other.gbDefraIndex == gbDefraIndex;
  }

  @override
  int get hashCode => Object.hash(
        co,
        no2,
        o3,
        so2,
        pm25,
        pm10,
        usEpaIndex,
        gbDefraIndex,
      );

  @override
  String toString() =>
      'AirQuality(pm2_5: $pm25, pm10: $pm10, EPA: $usEpaIndex)';
}

class CurrentWeather {
  const CurrentWeather({
    this.lastUpdatedEpoch = 0,
    this.lastUpdated = '',
    this.tempC = 0.0,
    this.tempF = 0.0,
    this.isDay = true,
    this.condition = const WeatherCondition(),
    this.windMph = 0.0,
    this.windKph = 0.0,
    this.windDegree = 0,
    this.windDir = '',
    this.pressureMb = 0.0,
    this.precipMm = 0.0,
    this.humidity = 0,
    this.cloud = 0,
    this.feelslikeC = 0.0,
    this.feelslikeF = 0.0,
    this.visKm = 0.0,
    this.uv = 0.0,
    this.gustKph = 0.0,
    this.airQuality,
  });

  final int lastUpdatedEpoch;
  final String lastUpdated;
  final double tempC;
  final double tempF;
  final bool isDay;
  final WeatherCondition condition;
  final double windMph;
  final double windKph;
  final int windDegree;
  final String windDir;
  final double pressureMb;
  final double precipMm;
  final int humidity;
  final int cloud;
  final double feelslikeC;
  final double feelslikeF;
  final double visKm;
  final double uv;
  final double gustKph;
  final AirQuality? airQuality;

  factory CurrentWeather.fromJson(Object? raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return CurrentWeather(
      lastUpdatedEpoch: readInt(json, 'last_updated_epoch', 0),
      lastUpdated: readString(json, 'last_updated', ''),
      tempC: readDouble(json, 'temp_c', 0.0),
      tempF: readDouble(json, 'temp_f', 0.0),
      isDay: readBool(json, 'is_day', true),
      condition: WeatherCondition.fromJson(json['condition']),
      windMph: readDouble(json, 'wind_mph', 0.0),
      windKph: readDouble(json, 'wind_kph', 0.0),
      windDegree: readInt(json, 'wind_degree', 0),
      windDir: readString(json, 'wind_dir', ''),
      pressureMb: readDouble(json, 'pressure_mb', 0.0),
      precipMm: readDouble(json, 'precip_mm', 0.0),
      humidity: readInt(json, 'humidity', 0),
      cloud: readInt(json, 'cloud', 0),
      feelslikeC: readDouble(json, 'feelslike_c', 0.0),
      feelslikeF: readDouble(json, 'feelslike_f', 0.0),
      visKm: readDouble(json, 'vis_km', 0.0),
      uv: readDouble(json, 'uv', 0.0),
      gustKph: readDouble(json, 'gust_kph', 0.0),
      airQuality: json.containsKey('air_quality')
          ? AirQuality.fromJson(json['air_quality'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'last_updated_epoch': lastUpdatedEpoch,
      'last_updated': lastUpdated,
      'temp_c': tempC,
      'temp_f': tempF,
      'is_day': isDay ? 1 : 0,
      'condition': condition.toJson(),
      'wind_mph': windMph,
      'wind_kph': windKph,
      'wind_degree': windDegree,
      'wind_dir': windDir,
      'pressure_mb': pressureMb,
      'precip_mm': precipMm,
      'humidity': humidity,
      'cloud': cloud,
      'feelslike_c': feelslikeC,
      'feelslike_f': feelslikeF,
      'vis_km': visKm,
      'uv': uv,
      'gust_kph': gustKph,
      if (airQuality != null) 'air_quality': airQuality!.toJson(),
    };
  }

  CurrentWeather copyWith({
    int? lastUpdatedEpoch,
    String? lastUpdated,
    double? tempC,
    double? tempF,
    bool? isDay,
    WeatherCondition? condition,
    double? windMph,
    double? windKph,
    int? windDegree,
    String? windDir,
    double? pressureMb,
    double? precipMm,
    int? humidity,
    int? cloud,
    double? feelslikeC,
    double? feelslikeF,
    double? visKm,
    double? uv,
    double? gustKph,
    AirQuality? airQuality,
  }) {
    return CurrentWeather(
      lastUpdatedEpoch: lastUpdatedEpoch ?? this.lastUpdatedEpoch,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      tempC: tempC ?? this.tempC,
      tempF: tempF ?? this.tempF,
      isDay: isDay ?? this.isDay,
      condition: condition ?? this.condition,
      windMph: windMph ?? this.windMph,
      windKph: windKph ?? this.windKph,
      windDegree: windDegree ?? this.windDegree,
      windDir: windDir ?? this.windDir,
      pressureMb: pressureMb ?? this.pressureMb,
      precipMm: precipMm ?? this.precipMm,
      humidity: humidity ?? this.humidity,
      cloud: cloud ?? this.cloud,
      feelslikeC: feelslikeC ?? this.feelslikeC,
      feelslikeF: feelslikeF ?? this.feelslikeF,
      visKm: visKm ?? this.visKm,
      uv: uv ?? this.uv,
      gustKph: gustKph ?? this.gustKph,
      airQuality: airQuality ?? this.airQuality,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CurrentWeather &&
        other.lastUpdatedEpoch == lastUpdatedEpoch &&
        other.lastUpdated == lastUpdated &&
        other.tempC == tempC &&
        other.tempF == tempF &&
        other.isDay == isDay &&
        other.condition == condition &&
        other.windMph == windMph &&
        other.windKph == windKph &&
        other.windDegree == windDegree &&
        other.windDir == windDir &&
        other.pressureMb == pressureMb &&
        other.precipMm == precipMm &&
        other.humidity == humidity &&
        other.cloud == cloud &&
        other.feelslikeC == feelslikeC &&
        other.feelslikeF == feelslikeF &&
        other.visKm == visKm &&
        other.uv == uv &&
        other.gustKph == gustKph &&
        other.airQuality == airQuality;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
        lastUpdatedEpoch,
        lastUpdated,
        tempC,
        tempF,
        isDay,
        condition,
        windMph,
        windKph,
        windDegree,
        windDir,
        pressureMb,
        precipMm,
        humidity,
        cloud,
        feelslikeC,
        feelslikeF,
        visKm,
        uv,
        gustKph,
        airQuality,
      ]);

  @override
  String toString() =>
      'CurrentWeather($tempC°C, ${condition.text}, Humidité: $humidity%)';
}

class WeatherAlert {
  const WeatherAlert({
    this.headline = '',
    this.msgtype = '',
    this.severity = '',
    this.urgency = '',
    this.areas = '',
    this.category = '',
    this.certainty = '',
    this.event = '',
    this.note = '',
    this.effective = '',
    this.expires = '',
    this.desc = '',
    this.instruction = '',
  });

  final String headline;
  final String msgtype;
  final String severity;
  final String urgency;
  final String areas;
  final String category;
  final String certainty;
  final String event;
  final String note;
  final String effective;
  final String expires;
  final String desc;
  final String instruction;

  factory WeatherAlert.fromJson(Object? raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return WeatherAlert(
      headline: readString(json, 'headline', ''),
      msgtype: readString(json, 'msgtype', ''),
      severity: readString(json, 'severity', ''),
      urgency: readString(json, 'urgency', ''),
      areas: readString(json, 'areas', ''),
      category: readString(json, 'category', ''),
      certainty: readString(json, 'certainty', ''),
      event: readString(json, 'event', ''),
      note: readString(json, 'note', ''),
      effective: readString(json, 'effective', ''),
      expires: readString(json, 'expires', ''),
      desc: readString(json, 'desc', ''),
      instruction: readString(json, 'instruction', ''),
    );
  }

  String get displayHeadline => _translateAlertText(headline);
  String get displayEvent => _translateAlertText(event);
  String get displayDesc => _translateAlertText(desc);
  String get displayInstruction => _translateAlertText(instruction);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'headline': headline,
      'msgtype': msgtype,
      'severity': severity,
      'urgency': urgency,
      'areas': areas,
      'category': category,
      'certainty': certainty,
      'event': event,
      'note': note,
      'effective': effective,
      'expires': expires,
      'desc': desc,
      'instruction': instruction,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is WeatherAlert &&
        other.headline == headline &&
        other.msgtype == msgtype &&
        other.severity == severity &&
        other.urgency == urgency &&
        other.areas == areas &&
        other.category == category &&
        other.certainty == certainty &&
        other.event == event &&
        other.note == note &&
        other.effective == effective &&
        other.expires == expires &&
        other.desc == desc &&
        other.instruction == instruction;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
        headline,
        msgtype,
        severity,
        urgency,
        areas,
        category,
        certainty,
        event,
        note,
        effective,
        expires,
        desc,
        instruction,
      ]);
}

class WeatherData {
  const WeatherData({
    this.location = const WeatherLocation(),
    this.current = const CurrentWeather(),
    this.alerts = const <WeatherAlert>[],
  });

  final WeatherLocation location;
  final CurrentWeather current;
  final List<WeatherAlert> alerts;

  factory WeatherData.fromJson(Object? raw) {
    final Map<String, dynamic> json = asJsonMap(raw);

    final List<WeatherAlert> alertList = <WeatherAlert>[];
    if (json.containsKey('alerts') && json['alerts'] is Map) {
      final Map<String, dynamic> alertsMap = asJsonMap(json['alerts']);
      if (alertsMap.containsKey('alert') && alertsMap['alert'] is List) {
        final List<dynamic> rawAlerts = alertsMap['alert'] as List<dynamic>;
        for (final dynamic item in rawAlerts) {
          alertList.add(WeatherAlert.fromJson(item));
        }
      }
    }

    return WeatherData(
      location: json.containsKey('location')
          ? WeatherLocation.fromJson(json['location'])
          : const WeatherLocation(),
      current: json.containsKey('current')
          ? CurrentWeather.fromJson(json['current'])
          : const CurrentWeather(),
      alerts: alertList,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'location': location.toJson(),
      'current': current.toJson(),
      'alerts': alerts.map((WeatherAlert a) => a.toJson()).toList(),
    };
  }

  WeatherData copyWith({
    WeatherLocation? location,
    CurrentWeather? current,
    List<WeatherAlert>? alerts,
  }) {
    return WeatherData(
      location: location ?? this.location,
      current: current ?? this.current,
      alerts: alerts ?? this.alerts,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! WeatherData) return false;
    if (other.location != location || other.current != current) return false;
    if (other.alerts.length != alerts.length) return false;
    for (int i = 0; i < alerts.length; i++) {
      if (other.alerts[i] != alerts[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(location, current, Object.hashAll(alerts));

  @override
  String toString() =>
      'WeatherData(location: ${location.name}, current: ${current.tempC}°C, alerts: ${alerts.length})';
}

String _translateAlertText(String input) {
  if (input.trim().isEmpty) return input;

  String text = input;

  const Map<String, String> exactTranslations = <String, String>{
    'Moderate high-temperature warning':
        'Alerte de température élevée (modérée)',
    'High-temperature warning': 'Alerte de température élevée',
    'Severe high-temperature warning': 'Alerte de forte chaleur / Canicule',
    'Extreme high-temperature warning': 'Alerte de canicule extrême',
    'Moderate damages may occur, especially in vulnerable or in exposed areas and to people who carry out weather-related activities.':
        'Des dommages modérés peuvent survenir, en particulier dans les zones vulnérables ou exposées et pour les personnes pratiquant des activités liées à la météo.',
    'Be careful, keep informed of the latest weather forecast.':
        'Soyez prudent, tenez-vous informé des dernières prévisions météo.',
  };

  if (exactTranslations.containsKey(text)) {
    return exactTranslations[text]!;
  }

  text = text
      .replaceAll(
        'Moderate high-temperature warning',
        'Alerte de température élevée (modérée)',
      )
      .replaceAll('High-temperature warning', 'Alerte de température élevée')
      .replaceAll(
        'Be careful, keep informed of the latest weather forecast.',
        'Soyez prudent, tenez-vous informé des dernières prévisions météo.',
      )
      .replaceAll(
        'Moderate damages may occur, especially in vulnerable or in exposed areas and to people who carry out weather-related activities.',
        'Des dommages modérés peuvent survenir, en particulier dans les zones vulnérables ou exposées et pour les personnes pratiquant des activités météo.',
      )
      .replaceAll('high-temperature warning', 'alerte de forte température')
      .replaceAll('temperature warning', 'alerte météo de température')
      .replaceAll('flood warning', 'alerte inondation')
      .replaceAll('wind warning', 'alerte vent fort')
      .replaceAll('thunderstorm warning', 'alerte orages')
      .replaceAll('warning', 'alerte');

  return text;
}
