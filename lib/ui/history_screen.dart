import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/readings_database.dart';
import '../models/ph_history_entry.dart';
import '../models/water_reading.dart';
import '../services/node_red_service.dart';
import '../state/providers.dart';
import '../state/water_readings_controller.dart';
import 'theme.dart';
import 'widgets/history_chart.dart';

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
  static const int _maxInfluxItems = 10;

  WaterParameter _shown = WaterParameter.ph;
  List<PhHistoryEntry> _influxPhEntries = <PhHistoryEntry>[];
  bool _isLoadingInflux = false;
  Timer? _influxTimer;

  @override
  void initState() {
    super.initState();
    _loadInfluxHistory();
    _startInfluxTimer();
  }

  @override
  void dispose() {
    _influxTimer?.cancel();
    super.dispose();
  }

  void _startInfluxTimer() {
    _influxTimer?.cancel();
    _influxTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _fetchPeriodicInfluxUpdate();
    });
  }

  Future<void> _loadInfluxHistory() async {
    setState(() => _isLoadingInflux = true);
    final List<PhHistoryEntry> entries =
        await NodeRedService().fetchAndLogPhHistory();
    if (mounted) {
      final List<PhHistoryEntry> sampledEntries =
          NodeRedService.filterLastEntriesSpacedBy(
        entries,
        maxCount: _maxInfluxItems,
        minInterval: const Duration(minutes: 5),
      );
      setState(() {
        _influxPhEntries = sampledEntries;
        _isLoadingInflux = false;
      });
    }
  }

  Future<void> _fetchPeriodicInfluxUpdate() async {
    final PhHistoryEntry? latestEntry =
        await NodeRedService().fetchLatestPhHistoryEntry();
    if (!mounted || latestEntry == null) return;

    if (_influxPhEntries.isNotEmpty &&
        _influxPhEntries.last.timestamp == latestEntry.timestamp) {
      return;
    }

    setState(() {
      final List<PhHistoryEntry> updated =
          List<PhHistoryEntry>.from(_influxPhEntries);
      updated.add(latestEntry);
      while (updated.length > _maxInfluxItems) {
        updated.removeAt(0);
      }
      _influxPhEntries = updated;
    });
  }

  Future<void> _testInfluxDbCall() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Interrogation Node-RED / InfluxDB...')),
    );
    await _loadInfluxHistory();
    _startInfluxTimer();
    messenger.hideCurrentSnackBar();
    if (!mounted) return;
    if (_influxPhEntries.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '✅ ${_influxPhEntries.length} mesures pH InfluxDB affichées sur le graphique',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('❌ Aucune donnée InfluxDB récupérée (vérifier Node-RED)'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

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

    final List<HistoryPoint> points;
    final bool isUsingInfluxForPh =
        _shown == WaterParameter.ph && _influxPhEntries.isNotEmpty;

    if (isUsingInfluxForPh) {
      final List<PhHistoryEntry> sorted = List<PhHistoryEntry>.from(_influxPhEntries)
        ..sort((PhHistoryEntry a, PhHistoryEntry b) => a.timestamp.compareTo(b.timestamp));
      points = sorted
          .map((PhHistoryEntry e) => HistoryPoint(e.timestamp.toLocal(), e.ph))
          .toList(growable: false);
    } else {
      points = state.recent.reversed
          .map((StoredReading stored) {
            final double? value = stored.reading.valueOf(_shown);
            return value == null
                ? null
                : HistoryPoint(stored.reading.takenAt.toLocal(), value);
          })
          .whereType<HistoryPoint>()
          .toList(growable: false);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
        actions: <Widget>[
          IconButton(
            icon: _isLoadingInflux
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Actualiser depuis InfluxDB',
            onPressed: _testInfluxDbCall,
          ),
        ],
      ),
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
