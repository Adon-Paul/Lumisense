import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lumisense/models/history_entry.dart';

const String _kHistoryEntries = 'historyEntries';
const int _kMaxEntries = 60;

class HistoryProvider extends ChangeNotifier {
  HistoryProvider({required SharedPreferences prefs}) : _prefs = prefs {
    _load();
  }

  final SharedPreferences _prefs;
  final List<HistoryEntry> _entries = <HistoryEntry>[];

  List<HistoryEntry> get entries => List<HistoryEntry>.unmodifiable(_entries);
  bool get hasEntries => _entries.isNotEmpty;

  Future<void> addEntry({
    required HistoryEntryType type,
    required String title,
    required String content,
  }) async {
    final String trimmedContent = content.trim();
    if (trimmedContent.isEmpty) {
      return;
    }

    _entries.insert(
      0,
      HistoryEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: type,
        title: title.trim().isEmpty ? 'Entry' : title.trim(),
        content: trimmedContent,
        createdAt: DateTime.now(),
      ),
    );

    if (_entries.length > _kMaxEntries) {
      _entries.removeRange(_kMaxEntries, _entries.length);
    }

    notifyListeners();
    await _persist();
  }

  Future<void> clearAll() async {
    if (_entries.isEmpty) {
      return;
    }
    _entries.clear();
    notifyListeners();
    await _prefs.remove(_kHistoryEntries);
  }

  void _load() {
    final String raw = _prefs.getString(_kHistoryEntries) ?? '';
    if (raw.isEmpty) {
      return;
    }

    try {
      _entries
        ..clear()
        ..addAll(HistoryEntry.decodeList(raw));
    } catch (_) {
      _entries.clear();
    }
  }

  Future<void> _persist() {
    return _prefs.setString(_kHistoryEntries, HistoryEntry.encodeList(_entries));
  }
}
