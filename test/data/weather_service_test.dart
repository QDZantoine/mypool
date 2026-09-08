import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mypool/services/weather-service.dart';
import 'package:mypool/models/weather_data.dart';

void main() {
  group('WeatherService', () {
    const String validJsonResponse = '''
{
  "location": {
    "name": "Marseille",
    "region": "Provence-Alpes-Cote d'Azur",
    "country": "France",
    "lat": 43.2965,
    "lon": 5.3698,
    "tz_id": "Europe/Paris",
    "localtime_epoch": 1700000000,
    "localtime": "2026-09-08 14:00"
  },
  "current": {
    "last_updated_epoch": 1700000000,
    "last_updated": "2026-09-08 14:00",
    "temp_c": 27.5,
    "temp_f": 81.5,
    "is_day": 1,
    "condition": {
      "text": "Soleil",
      "icon": "//cdn.weatherapi.com/weather/64x64/day/113.png",
      "code": 1000
    },
    "wind_mph": 8.0,
    "wind_kph": 12.9,
    "wind_degree": 210,
    "wind_dir": "SSW",
    "pressure_mb": 1018.0,
    "precip_mm": 0.0,
    "humidity": 50,
    "cloud": 0,
    "feelslike_c": 28.2,
    "feelslike_f": 82.8,
    "vis_km": 10.0,
    "uv": 7.0,
    "gust_kph": 18.0,
    "air_quality": {
      "co": 180.0,
      "no2": 8.0,
      "o3": 65.0,
      "so2": 2.0,
      "pm2_5": 5.0,
      "pm10": 9.0,
      "us-epa-index": 1,
      "gb-defra-index": 1
    }
  }
}
''';

    test('récupère avec succès les données météo pour une ville', () async {
      late Uri requestedUri;

      final MockClient client = MockClient((http.Request request) async {
        requestedUri = request.url;
        return http.Response(
          validJsonResponse,
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final WeatherService service = WeatherService(client: client);
      final WeatherData weather = await service.fetchCurrentWeather(
        'Marseille',
      );

      expect(requestedUri.scheme, 'http');
      expect(requestedUri.host, 'api.weatherapi.com');
      expect(requestedUri.path, '/v1/current.json');
      expect(requestedUri.queryParameters['key'], WeatherService.defaultApiKey);
      expect(requestedUri.queryParameters['q'], 'Marseille');
      expect(requestedUri.queryParameters['aqi'], 'yes');
      expect(requestedUri.queryParameters['lang'], 'fr');

      expect(weather.location.name, 'Marseille');
      expect(weather.current.tempC, 27.5);
      expect(weather.current.condition.text, 'Soleil');
    });

    test(
      'récupère avec succès les données météo par coordonnées GPS',
      () async {
        late Uri requestedUri;

        final MockClient client = MockClient((http.Request request) async {
          requestedUri = request.url;
          return http.Response(validJsonResponse, 200);
        });

        final WeatherService service = WeatherService(client: client);
        final WeatherData weather = await service
            .fetchCurrentWeatherByCoordinates(43.2965, 5.3698);

        expect(requestedUri.queryParameters['q'], '43.2965,5.3698');
        expect(weather.location.name, 'Marseille');
      },
    );

    test(
      'récupère avec succès les alertes météo sur l\'endpoint /v1/alerts.json',
      () async {
        late Uri requestedUri;

        final MockClient client = MockClient((http.Request request) async {
          requestedUri = request.url;
          return http.Response(validJsonResponse, 200);
        });

        final WeatherService service = WeatherService(client: client);
        final WeatherData weather = await service
            .fetchAlertWeatherByCoordinates(43.2965, 5.3698);

        expect(requestedUri.path, '/v1/alerts.json');
        expect(requestedUri.queryParameters['q'], '43.2965,5.3698');
        expect(weather.location.name, 'Marseille');
      },
    );

    test('lève une WeatherException si la ville transmise est vide', () async {
      final WeatherService service = WeatherService();

      expect(
        () => service.fetchCurrentWeather('   '),
        throwsA(isA<WeatherException>()),
      );
    });

    test('lève une WeatherException en cas d\'erreur HTTP (ex: 400)', () async {
      final MockClient client = MockClient((http.Request request) async {
        return http.Response(
          '{"error": {"code": 1006, "message": "No matching location found."}}',
          400,
        );
      });

      final WeatherService service = WeatherService(client: client);

      expect(
        () => service.fetchCurrentWeather('InexistanteCity12345'),
        throwsA(
          isA<WeatherException>().having(
            (WeatherException e) => e.statusCode,
            'statusCode',
            400,
          ),
        ),
      );
    });

    test('lève une WeatherException en cas de panne réseau', () async {
      final MockClient client = MockClient((http.Request request) async {
        throw Exception('SocketException: Failed host lookup');
      });

      final WeatherService service = WeatherService(client: client);

      expect(
        () => service.fetchCurrentWeather('Paris'),
        throwsA(isA<WeatherException>()),
      );
    });
  });
}
