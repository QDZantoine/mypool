import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/weather_data.dart';
import '../../state/providers.dart';

// Provider pour obtenir la position GPS réelle de l'utilisateur avec demande de permission
final userPositionProvider = FutureProvider.autoDispose<Position>((ref) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw Exception(
      'Les services de géolocalisation sont désactivés. Veuillez les activer sur votre appareil.',
    );
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw Exception(
        'Permission de géolocalisation refusée par l\'utilisateur.',
      );
    }
  }

  if (permission == LocationPermission.deniedForever) {
    throw Exception(
      'Permission de géolocalisation refusée définitivement. Veuillez l\'autoriser dans les paramètres de votre appareil.',
    );
  }

  // 1. Essaie d'abord de récupérer la dernière position connue (instantané)
  try {
    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) {
      return lastKnown;
    }
  } catch (_) {}

  // 2. Tente de récupérer la position actuelle avec un timeout de 5s pour l'émulateur
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 5),
      ),
    );
  } catch (_) {
    final lastKnownFallback = await Geolocator.getLastKnownPosition();
    if (lastKnownFallback != null) {
      return lastKnownFallback;
    }
    throw Exception(
      'Délai d\'attente GPS dépassé. Veuillez vérifier la localisation de votre appareil.',
    );
  }
});

// Providers pour la météo courante et les alertes basées sur la position de l'utilisateur
final currentWeatherCoordinatesProvider =
    FutureProvider.autoDispose<WeatherData>((ref) async {
      final position = await ref.watch(userPositionProvider.future);
      final service = ref.watch(weatherServiceProvider);
      final data = await service.fetchCurrentWeatherByCoordinates(
        position.latitude,
        position.longitude,
      );
      developer.log(
        const JsonEncoder.withIndent('  ').convert(data.toJson()),
        name: 'CurrentWeather',
      );
      return data;
    });

final alertWeatherCoordinatesProvider = FutureProvider.autoDispose<WeatherData>(
  (ref) async {
    final position = await ref.watch(userPositionProvider.future);
    final service = ref.watch(weatherServiceProvider);
    final data = await service.fetchAlertWeatherByCoordinates(
      position.latitude,
      position.longitude,
    );
    developer.log(
      const JsonEncoder.withIndent('  ').convert(data.toJson()),
      name: 'AlertWeather',
    );
    return data;
  },
);
