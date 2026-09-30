import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/models/ph_history_entry.dart';

void main() {
  group('PhHistoryEntry', () {
    test('parse un format brut InfluxDB (_value et _time) avec succès', () {
      final Map<String, dynamic> json = <String, dynamic>{
        '_time': '2026-09-29T14:28:55.94Z',
        '_value': 6.13,
        '_measurement': 'pool_ph',
        '_field': 'ph',
      };

      final PhHistoryEntry entry = PhHistoryEntry.fromJson(json);

      expect(entry.ph, 6.13);
      expect(entry.timestamp, DateTime.parse('2026-09-29T14:28:55.94Z'));
    });

    test('parse un JSON valide avec succès', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'timestamp': '2026-09-29T15:35:24.000Z',
        'ph': 7.36,
      };

      final PhHistoryEntry entry = PhHistoryEntry.fromJson(json);

      expect(entry.ph, 7.36);
      expect(entry.timestamp, DateTime.parse('2026-09-29T15:35:24.000Z'));
    });

    test('supporte un JSON corrompu ou incomplet sans planter', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'timestamp': 'invalid-date',
        'ph': '7,2',
      };

      final PhHistoryEntry entry = PhHistoryEntry.fromJson(json);

      expect(entry.ph, 7.2);
      expect(entry.timestamp, isA<DateTime>());
    });

    test('exporte en JSON correctement', () {
      final DateTime now = DateTime.utc(2026, 9, 29, 15, 30);
      final PhHistoryEntry entry = PhHistoryEntry(timestamp: now, ph: 7.2);

      final Map<String, dynamic> json = entry.toJson();

      expect(json['ph'], 7.2);
      expect(json['timestamp'], '2026-09-29T15:30:00.000Z');
    });
  });
}
