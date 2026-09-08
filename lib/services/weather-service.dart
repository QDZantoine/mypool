import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/weather_data.dart';

/// Exception levée lors d'un échec de récupération des données météo.
class WeatherException implements Exception {
  const WeatherException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'WeatherException: $message';
}

/// Service d'interaction avec l'API Météo (WeatherAPI).
///
/// Récupère les conditions météo actuelles et la qualité de l'air pour une ville
/// ou des coordonnées géographiques transmises dans le paramètre `q`.
class WeatherService {
  WeatherService({
    http.Client? client,
    this.apiKey = defaultApiKey,
    this.baseUrl = defaultCurrentBaseUrl,
    this.alertBaseUrl = defaultAlertBaseUrl,
  }) : _client = client ?? http.Client(),
       _isInternalClient = client == null;

  /// Clé API fournie par défaut pour le projet.
  static const String defaultApiKey = '8e87c09a99674e37abb90137260809';

  /// URL de base de l'endpoint des conditions courantes.
  static const String defaultCurrentBaseUrl =
      'http://api.weatherapi.com/v1/current.json';

  /// URL de base de l'endpoint des alertes météo.
  static const String defaultAlertBaseUrl =
      'http://api.weatherapi.com/v1/alerts.json';

  final http.Client _client;
  final bool _isInternalClient;
  final String apiKey;
  final String baseUrl;
  final String alertBaseUrl;

  /// Récupère les données météo courantes pour un lieu donné (nom de ville,
  /// coordonnées `"lat,lon"`, ou géolocalisation).
  ///
  /// Exemple d'URL appelée :
  /// `http://api.weatherapi.com/v1/current.json?key=8e87c09a99674e37abb90137260809&q=Paris&aqi=yes&lang=fr`
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
