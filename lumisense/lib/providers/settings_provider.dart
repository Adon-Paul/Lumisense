import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lumisense/services/tts_service.dart';

// ─── SharedPreferences keys ───────────────────────────────────────────────────
const String _kSpeechRate = 'speechRate';
const String _kVolume = 'ttsVolume';
const String _kPitch = 'ttsPitch';
const String _kEmergencyContact = 'emergencyContact';
const String _kPowerReadMode = 'powerReadMode';
// API keys are stored in secure storage, not SharedPreferences.
const String _kApiKey = 'geminiApiKey';
const String _kOrsApiKey = 'orsApiKey';
const String _kWeatherApiKey = 'weatherApiKey';
const String _kOpenRouterApiKey = 'openRouterApiKey';
const String _kGroqApiKey = 'groqApiKey';
const String _kOllamaServerUrl = 'ollamaServerUrl';

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
    _speechRate = _prefs.getDouble(_kSpeechRate) ?? 0.45;
    _volume = _prefs.getDouble(_kVolume) ?? 1.0;
    _pitch = _prefs.getDouble(_kPitch) ?? 1.0;
    _emergencyContact = _prefs.getString(_kEmergencyContact) ?? '';
    _powerReadMode = _prefs.getBool(_kPowerReadMode) ?? true;
    // API key is loaded asynchronously — call loadApiKey() after construction.
  }

  final SharedPreferences _prefs;
  final TtsService _tts;
  final FlutterSecureStorage _secureStorage;

  // ─── State ──────────────────────────────────────────────────────────────────

  double _speechRate = 0.45;
  double _volume = 1.0;
  double _pitch = 1.0;
  String _emergencyContact = '';
  String _apiKey = '';
  String _orsApiKey = '';
  String _weatherApiKey = '';
  String _openRouterApiKey = '';
  String _groqApiKey = '';
  String _ollamaServerUrl = '';
  bool _powerReadMode = true;

  // ─── Getters ─────────────────────────────────────────────────────────────────

  double get speechRate => _speechRate;
  double get volume => _volume;
  double get pitch => _pitch;
  String get emergencyContact => _emergencyContact;
  bool get powerReadMode => _powerReadMode;

  /// Returns the in-memory Gemini API key. Load it first with [loadApiKey].
  String get apiKey => _apiKey;

  /// Returns the in-memory ORS API key. Load it first with [loadApiKey].
  String get orsApiKey => _orsApiKey;

  bool get hasApiKey => _apiKey.isNotEmpty;
  bool get hasOrsApiKey => _orsApiKey.isNotEmpty;

  /// Returns the in-memory weather API key.
  String get weatherApiKey => _weatherApiKey;
  bool get hasWeatherApiKey => _weatherApiKey.isNotEmpty;

  /// Returns the in-memory OpenRouter API key (fallback when Gemini fails).
  String get openRouterApiKey => _openRouterApiKey;
  bool get hasOpenRouterApiKey => _openRouterApiKey.isNotEmpty;

  /// Returns the in-memory Groq API key.
  String get groqApiKey => _groqApiKey;
  bool get hasGroqApiKey => _groqApiKey.isNotEmpty;

  /// Returns the Ollama server URL (e.g. http://192.168.1.5:11434).
  String get ollamaServerUrl => _ollamaServerUrl;
  bool get hasOllamaServer => _ollamaServerUrl.isNotEmpty;

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

  /// Enables/disables chunked long-form reading mode for OCR results.
  Future<void> setPowerReadMode(bool value) async {
    if (_powerReadMode == value) return;
    _powerReadMode = value;
    await _prefs.setBool(_kPowerReadMode, value);
    notifyListeners();
  }

  // ─── API key (secure storage) ────────────────────────────────────────────────

  /// Loads API keys from secure storage into memory.
  /// Call this once after construction (e.g., in main() or a FutureProvider).
  Future<void> loadApiKey() async {
    bool changed = false;

    final String? stored = await _secureStorage.read(key: _kApiKey);
    if (stored != null && stored != _apiKey) {
      _apiKey = stored;
      changed = true;
    }

    final String? orsStored = await _secureStorage.read(key: _kOrsApiKey);
    if (orsStored != null && orsStored != _orsApiKey) {
      _orsApiKey = orsStored;
      changed = true;
    }

    final String? weatherStored =
        await _secureStorage.read(key: _kWeatherApiKey);
    if (weatherStored != null && weatherStored != _weatherApiKey) {
      _weatherApiKey = weatherStored;
      changed = true;
    }

    final String? openRouterStored =
        await _secureStorage.read(key: _kOpenRouterApiKey);
    if (openRouterStored != null && openRouterStored != _openRouterApiKey) {
      _openRouterApiKey = openRouterStored;
      changed = true;
    }

    final String? groqStored =
        await _secureStorage.read(key: _kGroqApiKey);
    if (groqStored != null && groqStored != _groqApiKey) {
      _groqApiKey = groqStored;
      changed = true;
    }

    final String? ollamaStored =
        await _secureStorage.read(key: _kOllamaServerUrl);
    if (ollamaStored != null && ollamaStored != _ollamaServerUrl) {
      _ollamaServerUrl = ollamaStored;
      changed = true;
    }

    if (changed) notifyListeners();
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

  /// Saves a new OpenRouteService API key to secure storage.
  Future<void> setOrsApiKey(String value) async {
    if (_orsApiKey == value) return;
    _orsApiKey = value;
    if (value.isEmpty) {
      await _secureStorage.delete(key: _kOrsApiKey);
    } else {
      await _secureStorage.write(key: _kOrsApiKey, value: value);
    }
    notifyListeners();
  }

  /// Saves a new OpenRouter API key to secure storage.
  Future<void> setOpenRouterApiKey(String value) async {
    if (_openRouterApiKey == value) return;
    _openRouterApiKey = value;
    if (value.isEmpty) {
      await _secureStorage.delete(key: _kOpenRouterApiKey);
    } else {
      await _secureStorage.write(key: _kOpenRouterApiKey, value: value);
    }
    notifyListeners();
  }

  /// Saves a new Groq API key to secure storage.
  Future<void> setGroqApiKey(String value) async {
    if (_groqApiKey == value) return;
    _groqApiKey = value;
    if (value.isEmpty) {
      await _secureStorage.delete(key: _kGroqApiKey);
    } else {
      await _secureStorage.write(key: _kGroqApiKey, value: value);
    }
    notifyListeners();
  }

  /// Saves the Ollama server URL to secure storage.
  Future<void> setOllamaServerUrl(String value) async {
    if (_ollamaServerUrl == value) return;
    _ollamaServerUrl = value;
    if (value.isEmpty) {
      await _secureStorage.delete(key: _kOllamaServerUrl);
    } else {
      await _secureStorage.write(key: _kOllamaServerUrl, value: value);
    }
    notifyListeners();
  }

  /// Saves a new OpenWeatherMap API key to secure storage.
  Future<void> setWeatherApiKey(String value) async {
    if (_weatherApiKey == value) return;
    _weatherApiKey = value;
    if (value.isEmpty) {
      await _secureStorage.delete(key: _kWeatherApiKey);
    } else {
      await _secureStorage.write(key: _kWeatherApiKey, value: value);
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
    String? orsApiKey,
    bool? powerReadMode,
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
      unawaited(
        apiKey.isEmpty
            ? _secureStorage.delete(key: _kApiKey)
            : _secureStorage.write(key: _kApiKey, value: apiKey),
      );
    }

    if (orsApiKey != null && _orsApiKey != orsApiKey) {
      _orsApiKey = orsApiKey;
      hasChanges = true;
      unawaited(
        orsApiKey.isEmpty
            ? _secureStorage.delete(key: _kOrsApiKey)
            : _secureStorage.write(key: _kOrsApiKey, value: orsApiKey),
      );
    }

    if (powerReadMode != null && _powerReadMode != powerReadMode) {
      _powerReadMode = powerReadMode;
      hasChanges = true;
      prefsWork.add(_prefs.setBool(_kPowerReadMode, powerReadMode));
    }

    if (hasChanges) {
      await Future.wait([...ttsWork, ...prefsWork]);
      notifyListeners();
    }
  }
}

// dart:async's unawaited() is used directly — imported above.
