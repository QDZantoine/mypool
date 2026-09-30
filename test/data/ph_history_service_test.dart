import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mypool/data/ph_history_service.dart';
import 'package:mypool/models/ph_history_entry.dart';

void main() {
  group('PhHistoryService', () {
    test('fetchAndLogPhHistory retourne les données décodées', () async {
      final MockClient client = MockClient((http.Request request) async {
        return http.Response(
          '''[
            {"timestamp": "2026-09-29T10:00:00.000Z", "ph": 7.2},
            {"timestamp": "2026-09-29T10:05:00.000Z", "ph": 7.3}
          ]''',
          200,
        );
      });

      final PhHistoryService service = PhHistoryService(client: client);
      final List<PhHistoryEntry> entries =
          await service.fetchAndLogPhHistory(baseUrl: 'http://localhost:1880');

      expect(entries.length, 2);
      expect(entries.first.ph, 7.2);
      expect(entries.last.ph, 7.3);
    });

    test('fetchLatestPhHistoryEntry retourne uniquement la dernière mesure (la plus récente)', () async {
      final MockClient client = MockClient((http.Request request) async {
        return http.Response(
          '''[
            {"timestamp": "2026-09-29T10:00:00.000Z", "ph": 7.1},
            {"timestamp": "2026-09-29T10:10:00.000Z", "ph": 7.5},
            {"timestamp": "2026-09-29T10:05:00.000Z", "ph": 7.3}
          ]''',
          200,
        );
      });

      final PhHistoryService service = PhHistoryService(client: client);
      final PhHistoryEntry? latest =
          await service.fetchLatestPhHistoryEntry(baseUrl: 'http://localhost:1880');

      expect(latest, isNotNull);
      expect(latest!.ph, 7.5);
      expect(latest.timestamp, DateTime.parse('2026-09-29T10:10:00.000Z'));
    });

    test('filterLastEntriesSpacedBy sélectionne les 10 dernières mesures espacées de 5 minutes', () {
      final List<PhHistoryEntry> entries = <PhHistoryEntry>[
        for (int i = 0; i < 20; i++)
          PhHistoryEntry(
            timestamp: DateTime.utc(2026, 9, 29, 10, i * 5), // Toutes les 5 min de 10:00 à 11:35
            ph: 7.0 + (i * 0.01),
          ),
      ];

      final List<PhHistoryEntry> filtered =
          PhHistoryService.filterLastEntriesSpacedBy(entries, maxCount: 10);

      expect(filtered.length, 10);
      expect(filtered.first.timestamp, DateTime.utc(2026, 9, 29, 10, 50));
      expect(filtered.last.timestamp, DateTime.utc(2026, 9, 29, 11, 35));
    });

    test('filterLastEntriesSpacedBy saute les données trop rapprochées (< 5 min)', () {
      final List<PhHistoryEntry> entries = <PhHistoryEntry>[
        PhHistoryEntry(timestamp: DateTime.utc(2026, 9, 29, 10, 0), ph: 7.0),
        PhHistoryEntry(timestamp: DateTime.utc(2026, 9, 29, 10, 2), ph: 7.1), // Ignoré
        PhHistoryEntry(timestamp: DateTime.utc(2026, 9, 29, 10, 5), ph: 7.2),
        PhHistoryEntry(timestamp: DateTime.utc(2026, 9, 29, 10, 8), ph: 7.3), // Ignoré
        PhHistoryEntry(timestamp: DateTime.utc(2026, 9, 29, 10, 10), ph: 7.4),
      ];

      final List<PhHistoryEntry> filtered =
          PhHistoryService.filterLastEntriesSpacedBy(entries, maxCount: 10);

      expect(filtered.map((e) => e.ph), <double>[7.0, 7.2, 7.4]);
    });
  });
}
