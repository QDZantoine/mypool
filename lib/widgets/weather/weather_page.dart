import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/weather_data.dart';
import 'weather_providers.dart';

class WeatherPage extends ConsumerWidget {
  const WeatherPage({
    super.key,
    this.title = 'Météo',
    this.showAppBar = false,
  });

  final String title;
  final bool showAppBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentWeatherAsync = ref.watch(currentWeatherCoordinatesProvider);
    final alertWeatherAsync = ref.watch(alertWeatherCoordinatesProvider);

    final content = RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(userPositionProvider);
        ref.invalidate(currentWeatherCoordinatesProvider);
        ref.invalidate(alertWeatherCoordinatesProvider);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _HeaderCard(),
            const SizedBox(height: 16),
            _WeatherSection(
              title: 'Météo Actuelle',
              icon: Icons.wb_sunny_outlined,
              weatherAsync: currentWeatherAsync,
              builder: (weather) => _WeatherDisplay(weather: weather),
            ),
            const SizedBox(height: 16),
            _WeatherSection(
              title: 'Alertes Météo',
              icon: Icons.warning_amber_rounded,
              weatherAsync: alertWeatherAsync,
              builder: (weather) => _AlertDisplay(weather: weather),
            ),
          ],
        ),
      ),
    );

    if (showAppBar) {
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          elevation: 2,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualiser la météo',
              onPressed: () {
                ref.invalidate(userPositionProvider);
                ref.invalidate(currentWeatherCoordinatesProvider);
                ref.invalidate(alertWeatherCoordinatesProvider);
              },
            ),
          ],
        ),
        body: content,
      );
    }

    return content;
  }
}

class _HeaderCard extends ConsumerWidget {
  const _HeaderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positionAsync = ref.watch(userPositionProvider);
    final currentWeatherAsync = ref.watch(currentWeatherCoordinatesProvider);

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              Icons.location_on,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  currentWeatherAsync.when(
                    data: (weather) => Text(
                      weather.location.country.isNotEmpty
                          ? '${weather.location.name}, ${weather.location.country}'
                          : weather.location.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    loading: () => Text(
                      'Recherche de la ville...',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer
                            .withAlpha(204),
                      ),
                    ),
                    error: (err, _) => Text(
                      'Ville non disponible',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer
                            .withAlpha(204),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  positionAsync.when(
                    data: (pos) => Text(
                      '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer
                            .withAlpha(178),
                      ),
                    ),
                    loading: () => Text(
                      'Recherche de la position GPS...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer
                            .withAlpha(178),
                      ),
                    ),
                    error: (err, _) => Text(
                      'Position non disponible',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherSection extends StatelessWidget {
  const _WeatherSection({
    required this.title,
    required this.icon,
    required this.weatherAsync,
    required this.builder,
  });

  final String title;
  final IconData icon;
  final AsyncValue<WeatherData> weatherAsync;
  final Widget Function(WeatherData weather) builder;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            weatherAsync.when(
              data: (weather) => builder(weather),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, stack) => Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  'Erreur : $err',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertDisplay extends StatelessWidget {
  const _AlertDisplay({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    if (weather.alerts.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.green.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withAlpha(100)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.green,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Pas d'alerte météo signalé",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.green.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final alert in weather.alerts)
          Card(
            color: Theme.of(context).colorScheme.errorContainer.withAlpha(50),
            margin: const EdgeInsets.only(bottom: 12.0),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          alert.displayEvent.isNotEmpty
                              ? alert.displayEvent
                              : (alert.displayHeadline.isNotEmpty
                                    ? alert.displayHeadline
                                    : 'Alerte Météo'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (alert.displayHeadline.isNotEmpty &&
                      alert.displayHeadline != alert.displayEvent) ...[
                    const SizedBox(height: 6),
                    Text(
                      alert.displayHeadline,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                  if (alert.displayDesc.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(alert.displayDesc),
                  ],
                  if (alert.displayInstruction.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Consignes : ${alert.displayInstruction}',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _WeatherDisplay extends StatelessWidget {
  const _WeatherDisplay({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final prettyJson = const JsonEncoder.withIndent('  ')
        .convert(weather.toJson());
    final airQuality = weather.current.airQuality;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${weather.current.tempC.toStringAsFixed(1)} °C',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    'Ressenti : ${weather.current.feelslikeC.toStringAsFixed(1)} °C',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Chip(
                  avatar: const Icon(Icons.wb_sunny, size: 18),
                  label: Text(weather.current.condition.text),
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .secondaryContainer,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricTile(
              label: 'Humidité',
              value: '${weather.current.humidity}%',
              icon: Icons.water_drop_outlined,
            ),
            _MetricTile(
              label: 'Vent',
              value:
                  '${weather.current.windKph} km/h (${weather.current.windDir})',
              icon: Icons.air_outlined,
            ),
            _MetricTile(
              label: 'Indice UV',
              value: '${weather.current.uv}',
              icon: Icons.wb_sunny,
            ),
            _MetricTile(
              label: 'Pression',
              value: '${weather.current.pressureMb} hPa',
              icon: Icons.speed_outlined,
            ),
            _MetricTile(
              label: 'Qualité Air (EPA)',
              value: airQuality != null ? '${airQuality.usEpaIndex}' : 'N/A',
              icon: Icons.air,
            ),
            _MetricTile(
              label: 'PM2.5',
              value: (airQuality != null && airQuality.pm25 != null)
                  ? '${airQuality.pm25!.toStringAsFixed(1)} µg/m³'
                  : 'N/A',
              icon: Icons.blur_on,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text(
            'Réponse JSON brute',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(13),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                prettyJson,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 155,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withAlpha(102),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
