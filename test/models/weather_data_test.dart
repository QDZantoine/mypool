import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/models/weather_data.dart';

void main() {
  group('WeatherData Model', () {
    final Map<String, dynamic> sampleJson = <String, dynamic>{
      'location': <String, dynamic>{
        'name': 'Paris',
        'region': 'Ile-de-France',
        'country': 'France',
        'lat': 48.8566,
        'lon': 2.3522,
        'tz_id': 'Europe/Paris',
        'localtime_epoch': 1700000000,
        'localtime': '2026-09-08 12:00',
      },
      'current': <String, dynamic>{
        'last_updated_epoch': 1700000000,
        'last_updated': '2026-09-08 12:00',
        'temp_c': 24.5,
        'temp_f': 76.1,
        'is_day': 1,
        'condition': <String, dynamic>{
          'text': 'Ensoleillé',
          'icon': '//cdn.weatherapi.com/weather/64x64/day/113.png',
          'code': 1000,
        },
        'wind_mph': 6.2,
        'wind_kph': 10.0,
        'wind_degree': 180,
        'wind_dir': 'S',
        'pressure_mb': 1015.0,
        'precip_mm': 0.0,
        'humidity': 45,
        'cloud': 10,
        'feelslike_c': 25.0,
        'feelslike_f': 77.0,
        'vis_km': 10.0,
        'uv': 6.0,
        'gust_kph': 15.0,
        'air_quality': <String, dynamic>{
          'co': 210.3,
          'no2': 12.1,
          'o3': 50.0,
          'so2': 3.5,
          'pm2_5': 7.5,
          'pm10': 12.0,
          'us-epa-index': 1,
          'gb-defra-index': 1,
        },
      },
    };

    test('désérialisation d\'un JSON WeatherAPI valide', () {
      final WeatherData weather = WeatherData.fromJson(sampleJson);

      expect(weather.location.name, 'Paris');
      expect(weather.location.region, 'Ile-de-France');
      expect(weather.location.country, 'France');
      expect(weather.location.lat, 48.8566);
      expect(weather.location.lon, 2.3522);
      expect(weather.location.tzId, 'Europe/Paris');

      expect(weather.current.tempC, 24.5);
      expect(weather.current.tempF, 76.1);
      expect(weather.current.isDay, isTrue);
      expect(weather.current.condition.text, 'Ensoleillé');
      expect(weather.current.condition.code, 1000);
      expect(weather.current.windKph, 10.0);
      expect(weather.current.humidity, 45);
      expect(weather.current.airQuality, isNotNull);
      expect(weather.current.airQuality?.pm25, 7.5);
      expect(weather.current.airQuality?.usEpaIndex, 1);
    });

    test('tolérance aux données corrompues ou nulles (fromJson)', () {
      final WeatherData weather = WeatherData.fromJson(<String, dynamic>{
        'location': null,
        'current': 'invalid_type',
      });

      expect(weather.location.name, '');
      expect(weather.location.lat, 0.0);
      expect(weather.current.tempC, 0.0);
      expect(weather.current.isDay, isTrue);
      expect(weather.current.condition.text, '');
      expect(weather.current.airQuality, isNull);
    });

    test('aller-retour JSON (toJson / fromJson)', () {
      final WeatherData original = WeatherData.fromJson(sampleJson);
      final Map<String, dynamic> jsonMap = original.toJson();
      final WeatherData reconstructed = WeatherData.fromJson(jsonMap);

      expect(reconstructed, equals(original));
      expect(reconstructed.hashCode, equals(original.hashCode));
    });

    test('modification immuable avec copyWith', () {
      final WeatherData original = WeatherData.fromJson(sampleJson);
      final WeatherData updated = original.copyWith(
        current: original.current.copyWith(tempC: 28.0),
      );

      expect(updated.current.tempC, 28.0);
      expect(original.current.tempC, 24.5);
      expect(updated.location, equals(original.location));
    });
  });
}
