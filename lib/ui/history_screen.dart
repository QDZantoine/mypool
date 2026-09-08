import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/readings_database.dart';
import '../models/water_reading.dart';
import '../state/providers.dart';
import '../state/water_readings_controller.dart';
import 'theme.dart';
import 'widgets/history_chart.dart';

/// Historique des mesures : une courbe par paramètre, et la liste.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen()));
  }

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  WaterParameter _shown = WaterParameter.ph;

  /// Les paramètres dont une courbe a du sens.
  ///
  /// Le chlore combiné et le sel n'y sont pas : le premier se lit en tout ou
  /// rien, le second ne bouge qu'aux remplissages.
  static const List<WaterParameter> _chartable = <WaterParameter>[
    WaterParameter.ph,
    WaterParameter.freeChlorine,
    WaterParameter.tac,
    WaterParameter.th,
    WaterParameter.stabilizer,
    WaterParameter.temperature,
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ReadingsState state = ref.watch(readingsProvider);

    // L'ordre d'affichage de la courbe est chronologique, l'inverse de la
    // liste : une courbe se lit de gauche à droite.
    final List<HistoryPoint> points = state.recent.reversed
        .map((StoredReading stored) {
          final double? value = stored.reading.valueOf(_shown);
          return value == null
              ? null
              : HistoryPoint(stored.reading.takenAt.toLocal(), value);
        })
        .whereType<HistoryPoint>()
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Historique')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: <Widget>[
                for (final WaterParameter parameter in _chartable)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(parameter.label),
                      selected: _shown == parameter,
                      onSelected: (bool selected) {
                        if (selected) {
                          setState(() => _shown = parameter);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _shown.unit.isEmpty
                        ? _shown.label
                        : '${_shown.label} (${_shown.unit})',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  HistoryChart(parameter: _shown, points: points),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 16,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppTheme.inRange.withValues(alpha: 0.3),
                          border: Border.all(
                            color: AppTheme.inRange.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'plage conseillée',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 16, bottom: 4),
            child: Text(
              '${state.recent.length} mesure'
              '${state.recent.length == 1 ? '' : 's'}',
              style: theme.textTheme.titleLarge,
            ),
          ),
          for (final StoredReading stored in state.recent)
            _ReadingRow(
              stored: stored,
              onDelete: () =>
                  ref.read(readingsProvider.notifier).delete(stored.id),
            ),
          if (state.recent.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Aucune mesure enregistrée pour l’instant.',
                style: theme.textTheme.bodyLarge,
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({required this.stored, required this.onDelete});

  final StoredReading stored;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final WaterReading reading = stored.reading;
    final DateTime local = reading.takenAt.toLocal();

    // Résumé compact : seules les valeurs présentes apparaissent.
    final List<String> parts = <String>[
      for (final WaterParameter parameter in WaterParameter.values)
        if (reading.valueOf(parameter) != null)
          '${parameter.label} ${parameter.formatValue(reading.valueOf(parameter)!)}',
    ];

    return Card(
      child: ListTile(
        leading: Icon(
          reading.source == MeasurementSource.sensor
              ? Icons.sensors
              : Icons.edit_note,
          color: theme.colorScheme.outline,
        ),
        title: Text(
          '${local.day.toString().padLeft(2, '0')}/'
          '${local.month.toString().padLeft(2, '0')} à '
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}',
          style: theme.textTheme.titleMedium,
        ),
        subtitle: Text(parts.join(' · ')),
        trailing: IconButton(
          tooltip: 'Supprimer cette mesure',
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
        ),
        isThreeLine: parts.length > 3,
      ),
    );
  }
}
