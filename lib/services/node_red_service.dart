import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../models/ph_history_entry.dart';

/// Service d'interrogation et de gestion des données transmises par Node-RED / InfluxDB.
class NodeRedService {
  NodeRedService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Récupère l'historique du pH depuis Node-RED et logue les résultats.
  ///
  /// Note pour Android Emulator : utiliser '10.0.2.2' au lieu de 'localhost'.
  Future<List<PhHistoryEntry>> fetchAndLogPhHistory({
    String? baseUrl,
  }) async {
    final List<String> targets = baseUrl != null
        ? <String>[baseUrl]
        : <String>['http://10.0.2.2:1880', 'http://localhost:1880'];

    for (final String host in targets) {
      final Uri url = Uri.parse('$host/api/ph-history');
      developer.log(
        'Interrogation de $url...',
        name: 'NodeRedService',
      );

      try {
        final http.Response response =
            await _client.get(url).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final Object? decoded = jsonDecode(response.body);
          if (decoded is List) {
            final List<PhHistoryEntry> entries = decoded
                .whereType<Map<String, dynamic>>()
                .map(PhHistoryEntry.fromJson)
                .toList();

            developer.log(
              '✅ ${entries.length} mesures pH récupérées depuis InfluxDB :',
              name: 'NodeRedService',
            );

            for (final PhHistoryEntry entry in entries) {
              developer.log(
                '  - [${entry.timestamp.toIso8601String()}] pH = ${entry.ph}',
                name: 'NodeRedService',
              );
            }

            return entries;
          }
        }
      } catch (e) {
        developer.log(
          'Échec sur $host ($e), essai du suivant si disponible...',
          name: 'NodeRedService',
        );
      }
    }

    developer.log(
      '❌ Aucune donnée récupérée depuis l\'API Node-RED',
      name: 'NodeRedService',
    );

    return const <PhHistoryEntry>[];
  }

  /// Récupère la dernière mesure pH écrite en BDD depuis Node-RED.
  Future<PhHistoryEntry?> fetchLatestPhHistoryEntry({
    String? baseUrl,
  }) async {
    final List<PhHistoryEntry> entries =
        await fetchAndLogPhHistory(baseUrl: baseUrl);
    if (entries.isEmpty) return null;
    final List<PhHistoryEntry> sorted = List<PhHistoryEntry>.from(entries)
      ..sort((PhHistoryEntry a, PhHistoryEntry b) =>
          a.timestamp.compareTo(b.timestamp));
    return sorted.last;
  }

  /// Filtre et échantillonne les mesures pour conserver au maximum [maxCount] mesures
  /// espacées d'au moins [minInterval] (par défaut 5 minutes), en partant de la plus récente.
  /// Le résultat est retourné dans l'ordre chronologique.
  static List<PhHistoryEntry> filterLastEntriesSpacedBy(
    List<PhHistoryEntry> entries, {
    int maxCount = 10,
    Duration minInterval = const Duration(minutes: 5),
  }) {
    if (entries.isEmpty) return <PhHistoryEntry>[];

    final List<PhHistoryEntry> sorted = List<PhHistoryEntry>.from(entries)
      ..sort((PhHistoryEntry a, PhHistoryEntry b) =>
          a.timestamp.compareTo(b.timestamp));

    final List<PhHistoryEntry> selected = <PhHistoryEntry>[sorted.last];
    DateTime lastSelectedTime = sorted.last.timestamp;

    for (int i = sorted.length - 2; i >= 0; i--) {
      final PhHistoryEntry current = sorted[i];
      if (lastSelectedTime.difference(current.timestamp) >= minInterval) {
        selected.add(current);
        lastSelectedTime = current.timestamp;
        if (selected.length >= maxCount) {
          break;
        }
      }
    }

    selected.sort((PhHistoryEntry a, PhHistoryEntry b) =>
        a.timestamp.compareTo(b.timestamp));
    return selected;
  }
}

/// Alias de compatibilité pour PhHistoryService.
typedef PhHistoryService = NodeRedService;
