import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/weather_data.dart';

class WeatherException implements Exception {
  const WeatherException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'WeatherException: $message';
}

class WeatherService {
  WeatherService({
    http.Client? client,
    String? apiKey,
    String? baseUrl,
    String? alertBaseUrl,
  }) : _client = client ?? http.Client(),
       _isInternalClient = client == null,
       apiKey = apiKey ?? defaultApiKey,
       baseUrl = baseUrl ?? defaultCurrentBaseUrl,
       alertBaseUrl = alertBaseUrl ?? defaultAlertBaseUrl;

  static String get defaultApiKey {
    if (dotenv.isInitialized) {
      return dotenv.env['WEATHER_API_KEY'] ?? '8e87c09a99674e37abb90137260809';
    }
    return '8e87c09a99674e37abb90137260809';
  }

  static String get defaultCurrentBaseUrl {
    final base = dotenv.isInitialized
        ? (dotenv.env['API_BASE_URL'] ?? 'https://api.weatherapi.com/v1/')
        : 'https://api.weatherapi.com/v1/';
    final cleanBase = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return '$cleanBase/current.json';
  }

  static String get defaultAlertBaseUrl {
    final base = dotenv.isInitialized
        ? (dotenv.env['API_BASE_URL'] ?? 'https://api.weatherapi.com/v1/')
        : 'https://api.weatherapi.com/v1/';
    final cleanBase = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return '$cleanBase/alerts.json';
  }

  final http.Client _client;
  final bool _isInternalClient;
  final String apiKey;
  final String baseUrl;
  final String alertBaseUrl;

  Future<WeatherData> fetchCurrentWeather(
    String location, {
    bool aqi = true,
    String lang = 'fr',
  }) async {
    if (location.trim().isEmpty) {
      throw const WeatherException(
        'Impossible de localiser l\'utilisateur. Veuillez activer la localisation et accepter les permissions de géolocalisation.',
      );
    }

    final Uri uri = Uri.parse(baseUrl).replace(
      queryParameters: <String, String>{
        'key': apiKey,
        'q': location.trim(),
        'aqi': aqi ? 'yes' : 'no',
        'lang': lang,
      },
    );

    try {
      final http.Response response = await _client.get(uri);

      if (response.statusCode == 200) {
        final Object? decoded = jsonDecode(response.body);
        return WeatherData.fromJson(decoded);
      } else {
        throw WeatherException(
          'Impossible de récupérer la météo pour "$location" (code HTTP ${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    } on WeatherException {
      rethrow;
    } catch (e) {
      throw WeatherException(
        'Erreur lors de la connexion au service météo : $e',
      );
    }
  }

  Future<WeatherData> fetchAlertWeather(
    String location, {
    bool aqi = true,
    String lang = 'fr',
  }) async {
    if (location.trim().isEmpty) {
      throw const WeatherException(
        'Impossible de localiser l\'utilisateur. Veuillez activer la localisation et accepter les permissions de géolocalisation.',
      );
    }

    final Uri uri = Uri.parse(alertBaseUrl).replace(
      queryParameters: <String, String>{
        'key': apiKey,
        'q': location.trim(),
        'aqi': aqi ? 'yes' : 'no',
        'lang': lang,
      },
    );

    try {
      final http.Response response = await _client.get(uri);

      if (response.statusCode == 200) {
        final Object? decoded = jsonDecode(response.body);
        return WeatherData.fromJson(decoded);
      } else {
        throw WeatherException(
          'Impossible de récupérer les alertes météo pour "$location" (code HTTP ${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    } on WeatherException {
      rethrow;
    } catch (e) {
      throw WeatherException(
        'Erreur lors de la connexion au service météo : $e',
      );
    }
  }

  Future<WeatherData> fetchCurrentWeatherByCoordinates(
    double latitude,
    double longitude, {
    bool aqi = true,
    String lang = 'fr',
  }) {
    return fetchCurrentWeather('$latitude,$longitude', aqi: aqi, lang: lang);
  }

  Future<WeatherData> fetchAlertWeatherByCoordinates(
    double latitude,
    double longitude, {
    bool aqi = true,
    String lang = 'fr',
  }) {
    return fetchAlertWeather('$latitude,$longitude', aqi: aqi, lang: lang);
  }

  void dispose() {
    if (_isInternalClient) {
      _client.close();
    }
  }
}
