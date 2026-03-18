import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lumisense/services/tts_service.dart';

// ─── SharedPreferences keys ───────────────────────────────────────────────────
const String _kSpeechRate = 'speechRate';
const String _kVolume = 'ttsVolume';
const String _kPitch = 'ttsPitch';
const String _kEmergencyContact = 'emergencyContact';
// API key is stored in secure storage, not SharedPreferences.
const String _kApiKey = 'geminiApiKey';

/// Stores and persists user-configurable app settings.
///
/// - Non-sensitive settings (speech rate, volume, pitch, emergency contact)
///   are persisted via [SharedPreferences].
/// - The Gemini API key is persisted via [FlutterSecureStorage] so it is
///   never written to plain-text SharedPreferences XML on Android.
/// - Any change to TTS-related settings is immediately forwarded to
///   [TtsService] so the engine reflects the new value in real time.
///
/// Obtain the single instance via Provider:
/// ```dart
/// context.read<SettingsProvider>()
/// ```
class SettingsProvider extends ChangeNotifier {
  SettingsProvider({
    required SharedPreferences prefs,
    required TtsService tts,
    required FlutterSecureStorage secureStorage,
  })  : _prefs = prefs,
        _tts = tts,
        _secureStorage = secureStorage {
    // Load non-sensitive settings synchronously from the already-loaded prefs
    // instance (no async work needed — SharedPreferences.getInstance() was
    // awaited in main() before the widget tree started).
    _speechRate = _prefs.getDouble(_kSpeechRate) ?? 0.5;
    _volume = _prefs.getDouble(_kVolume) ?? 1.0;
    _pitch = _prefs.getDouble(_kPitch) ?? 1.0;
    _emergencyContact = _prefs.getString(_kEmergencyContact) ?? '';
    // API key is loaded asynchronously — call loadApiKey() after construction.
  }

  final SharedPreferences _prefs;
  final TtsService _tts;
  final FlutterSecureStorage _secureStorage;

  // ─── State ──────────────────────────────────────────────────────────────────

  double _speechRate = 0.5;
  double _volume = 1.0;
  double _pitch = 1.0;
  String _emergencyContact = '';
  String _apiKey = '';

  // ─── Getters ─────────────────────────────────────────────────────────────────

  double get speechRate => _speechRate;
  double get volume => _volume;
  double get pitch => _pitch;
  String get emergencyContact => _emergencyContact;

  /// Returns the in-memory API key. Load it first with [loadApiKey].
  String get apiKey => _apiKey;

  bool get hasApiKey => _apiKey.isNotEmpty;
  bool get hasEmergencyContact => _emergencyContact.isNotEmpty;

  // ─── TTS settings (async — bridge to TtsService) ─────────────────────────

  /// Updates speech rate, persists it, and forwards to the TTS engine.
  Future<void> setSpeechRate(double value) async {
    final double clamped = value.clamp(0.0, 1.0);
    if (_speechRate == clamped) return;
    _speechRate = clamped;
    await Future.wait([
      _prefs.setDouble(_kSpeechRate, clamped),
      _tts.setSpeechRate(clamped),
    ]);
    notifyListeners();
  }

  /// Updates TTS volume, persists it, and forwards to the TTS engine.
  Future<void> setVolume(double value) async {
    final double clamped = value.clamp(0.0, 1.0);
    if (_volume == clamped) return;
    _volume = clamped;
    await Future.wait([
      _prefs.setDouble(_kVolume, clamped),
      _tts.setVolume(clamped),
    ]);
    notifyListeners();
  }

  /// Updates TTS pitch, persists it, and forwards to the TTS engine.
  Future<void> setPitch(double value) async {
    final double clamped = value.clamp(0.5, 2.0);
    if (_pitch == clamped) return;
    _pitch = clamped;
    await Future.wait([
      _prefs.setDouble(_kPitch, clamped),
      _tts.setPitch(clamped),
    ]);
    notifyListeners();
  }

  // ─── Non-TTS settings ────────────────────────────────────────────────────────

  /// Updates the emergency contact number and persists it.
  Future<void> setEmergencyContact(String value) async {
    if (_emergencyContact == value) return;
    _emergencyContact = value;
    await _prefs.setString(_kEmergencyContact, value);
    notifyListeners();
  }

  // ─── API key (secure storage) ────────────────────────────────────────────────

  /// Loads the Gemini API key from secure storage into memory.
  /// Call this once after construction (e.g., in main() or a FutureProvider).
  Future<void> loadApiKey() async {
    final String? stored = await _secureStorage.read(key: _kApiKey);
    if (stored != null && stored != _apiKey) {
      _apiKey = stored;
      notifyListeners();
    }
  }

  /// Saves a new Gemini API key to secure storage.
  Future<void> setApiKey(String value) async {
    if (_apiKey == value) return;
    _apiKey = value;
    if (value.isEmpty) {
      await _secureStorage.delete(key: _kApiKey);
    } else {
      await _secureStorage.write(key: _kApiKey, value: value);
    }
    notifyListeners();
  }

  // ─── Batch update ────────────────────────────────────────────────────────────

  /// Convenience helper to update multiple settings in one operation.
  /// TTS engine changes are applied concurrently; only one [notifyListeners]
  /// is fired at the end.
  Future<void> updateSettings({
    double? speechRate,
    double? volume,
    double? pitch,
    String? emergencyContact,
    String? apiKey,
  }) async {
    bool hasChanges = false;
    final List<Future<void>> ttsWork = [];
    final List<Future<bool>> prefsWork = [];

    if (speechRate != null) {
      final double c = speechRate.clamp(0.0, 1.0);
      if (_speechRate != c) {
        _speechRate = c;
        hasChanges = true;
        ttsWork.add(_tts.setSpeechRate(c));
        prefsWork.add(_prefs.setDouble(_kSpeechRate, c));
      }
    }

    if (volume != null) {
      final double c = volume.clamp(0.0, 1.0);
      if (_volume != c) {
        _volume = c;
        hasChanges = true;
        ttsWork.add(_tts.setVolume(c));
        prefsWork.add(_prefs.setDouble(_kVolume, c));
      }
    }

    if (pitch != null) {
      final double c = pitch.clamp(0.5, 2.0);
      if (_pitch != c) {
        _pitch = c;
        hasChanges = true;
        ttsWork.add(_tts.setPitch(c));
        prefsWork.add(_prefs.setDouble(_kPitch, c));
      }
    }

    if (emergencyContact != null && _emergencyContact != emergencyContact) {
      _emergencyContact = emergencyContact;
      hasChanges = true;
      prefsWork.add(_prefs.setString(_kEmergencyContact, emergencyContact));
    }

    if (apiKey != null && _apiKey != apiKey) {
      _apiKey = apiKey;
      hasChanges = true;
      // API key write is fire-and-forget here to keep the Future<void> type
      // consistent; errors are swallowed intentionally in batch mode.
      unawaited(
        apiKey.isEmpty
            ? _secureStorage.delete(key: _kApiKey)
            : _secureStorage.write(key: _kApiKey, value: apiKey),
      );
    }

    if (hasChanges) {
      await Future.wait([...ttsWork, ...prefsWork]);
      notifyListeners();
    }
  }
}

/// Convenience extension to discard a future intentionally.
extension on Future<void> {
  // ignore: unused_element
  void get unawaited => then((_) {}, onError: (_) {});
}

// Standalone helper for use inside updateSettings.
void unawaited(Future<void> future) {
  future.then((_) {}).catchError((_) {});
}
