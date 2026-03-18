import 'package:flutter_test/flutter_test.dart';
import 'package:lumisense/models/history_entry.dart';

void main() {
  group('HistoryEntry encode/decode', () {
    test('round-trips entries including scene description type', () {
      final List<HistoryEntry> entries = <HistoryEntry>[
        HistoryEntry(
          id: '1',
          type: HistoryEntryType.ocr,
          title: 'Read',
          content: 'Sample OCR text',
          createdAt: DateTime(2026, 1, 1),
        ),
        HistoryEntry(
          id: '2',
          type: HistoryEntryType.sceneDescription,
          title: 'Describe',
          content: 'A table is ahead of you.',
          createdAt: DateTime(2026, 1, 2),
        ),
      ];

      final String raw = HistoryEntry.encodeList(entries);
      final List<HistoryEntry> decoded = HistoryEntry.decodeList(raw);

      expect(decoded.length, 2);
      expect(decoded[0].type, HistoryEntryType.ocr);
      expect(decoded[1].type, HistoryEntryType.sceneDescription);
      expect(decoded[1].content, contains('table'));
    });
  });
}
