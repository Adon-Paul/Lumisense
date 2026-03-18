import 'dart:convert';

enum HistoryEntryType {
  ocr,
  objectDetection,
  sceneDescription,
}

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final HistoryEntryType type;
  final String title;
  final String content;
  final DateTime createdAt;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'type': type.name,
      'title': title,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory HistoryEntry.fromMap(Map<String, dynamic> map) {
    final String typeRaw = (map['type'] as String?) ?? HistoryEntryType.ocr.name;
    return HistoryEntry(
      id: (map['id'] as String?) ?? DateTime.now().microsecondsSinceEpoch.toString(),
      type: HistoryEntryType.values.firstWhere(
        (item) => item.name == typeRaw,
        orElse: () => HistoryEntryType.ocr,
      ),
      title: (map['title'] as String?) ?? 'Entry',
      content: (map['content'] as String?) ?? '',
      createdAt: DateTime.tryParse((map['createdAt'] as String?) ?? '') ?? DateTime.now(),
    );
  }

  static String encodeList(List<HistoryEntry> entries) {
    return jsonEncode(entries.map((e) => e.toMap()).toList(growable: false));
  }

  static List<HistoryEntry> decodeList(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <HistoryEntry>[];
    }

    return decoded
        .whereType<Map>()
        .map((item) => HistoryEntry.fromMap(item.cast<String, dynamic>()))
        .toList(growable: false);
  }
}
