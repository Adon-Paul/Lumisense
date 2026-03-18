import 'package:flutter_test/flutter_test.dart';
import 'package:lumisense/models/history_entry.dart';
import 'package:lumisense/providers/history_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('HistoryProvider', () {
    test('adds, persists and clears entries', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final HistoryProvider provider = HistoryProvider(prefs: prefs);
      expect(provider.hasEntries, isFalse);

      await provider.addEntry(
        type: HistoryEntryType.objectDetection,
        title: 'Objects',
        content: 'chair, table',
      );

      expect(provider.hasEntries, isTrue);
      expect(provider.entries.first.title, 'Objects');

      final HistoryProvider reloaded = HistoryProvider(prefs: prefs);
      expect(reloaded.entries.length, 1);
      expect(reloaded.entries.first.content, contains('chair'));

      await reloaded.clearAll();
      expect(reloaded.hasEntries, isFalse);
      expect(prefs.getString('historyEntries'), isNull);
    });

    test('caps list at max 60 entries', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final HistoryProvider provider = HistoryProvider(prefs: prefs);

      for (int i = 0; i < 65; i++) {
        await provider.addEntry(
          type: HistoryEntryType.ocr,
          title: 'Entry $i',
          content: 'content $i',
        );
      }

      expect(provider.entries.length, 60);
      expect(provider.entries.first.title, 'Entry 64');
      expect(provider.entries.last.title, 'Entry 5');
    });
  });
}
