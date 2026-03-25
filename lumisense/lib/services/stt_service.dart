import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Voice command recognised by the STT engine, mapped to an app action.
enum VoiceCommand {
  readText,
  identifyObjects,
  describeScene,
  navigation,
  navigateTo,
  repeatDirection,
  whereAmI,
  scanPayment,
  identifyCurrency,
  checkBrightness,
  checkWeather,
  callContact,
  detectPeople,
  toggleOnDevice,
  help,
  sos,
  stop,
  unknown,
}

/// Callback signature for when a voice command is recognised.
typedef OnVoiceCommandCallback = void Function(
    VoiceCommand command, String rawText);

/// Wraps [SpeechToText] for voice command recognition with optional
/// continuous listening.
///
/// In continuous mode the mic restarts automatically after each command
/// and after TTS finishes, giving visually impaired users a hands-free
/// experience.
class SttService {
  SttService();

  final SpeechToText _speech = SpeechToText();

  bool _isInitialized = false;
  bool _isListening = false;

  /// Master switch for continuous mode.
  bool _continuousMode = false;

  /// Set while TTS is speaking — suppresses auto-restart.
  bool _mutedForTts = false;

  /// Guards against overlapping restart attempts.
  bool _restartScheduled = false;

  /// Called when a final voice command is recognised.
  OnVoiceCommandCallback? onCommand;

  /// Called when the listening status changes (started / stopped).
  ValueChanged<bool>? onListeningChanged;

  // ─── Public getters ──────────────────────────────────────────────────────

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  bool get isAvailable => _isInitialized && _speech.isAvailable;
  bool get continuousMode => _continuousMode;

  // ─── Initialization ──────────────────────────────────────────────────────

  Future<bool> init() async {
    if (_isInitialized) return _speech.isAvailable;

    try {
      final bool available = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
        debugLogging: kDebugMode,
      );
      if (available) _isInitialized = true;
      return available;
    } catch (e) {
      debugPrint('SttService init failed: $e');
      return false;
    }
  }

  // ─── Continuous mode ─────────────────────────────────────────────────────

  void setContinuousMode(bool enabled) {
    _continuousMode = enabled;
    if (!enabled) {
      _mutedForTts = false;
      _restartScheduled = false;
    }
  }

  /// Call before TTS starts speaking — stops the mic so it won't hear itself.
  Future<void> pauseForTts() async {
    if (!_continuousMode) return;
    _mutedForTts = true;
    _restartScheduled = false;
    if (_isListening) {
      await _speech.cancel();
      _setListening(false);
    }
  }

  /// Call after TTS finishes — restarts the mic if continuous mode is on.
  void resumeAfterTts() {
    if (!_continuousMode) return;
    _mutedForTts = false;
    _scheduleRestart();
  }

  // ─── Listening control ───────────────────────────────────────────────────

  Future<void> startListening() async {
    if (!_isInitialized || !_speech.isAvailable) return;
    if (_isListening) return;

    _mutedForTts = false;

    try {
      await _speech.listen(
        onResult: _onResult,
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        localeId: 'en_US',
        listenOptions: SpeechListenOptions(
          partialResults: false,
          listenMode: ListenMode.confirmation,
        ),
      );
      _setListening(true);
    } catch (e) {
      debugPrint('SttService: startListening failed: $e');
      _setListening(false);
      // Retry once after a delay in continuous mode
      if (_continuousMode && !_mutedForTts) {
        _scheduleRestart();
      }
    }
  }

  Future<void> stopListening() async {
    _continuousMode = false;
    _mutedForTts = false;
    _restartScheduled = false;
    if (!_isListening) return;
    await _speech.stop();
    _setListening(false);
  }

  Future<void> cancelListening() async {
    _restartScheduled = false;
    if (!_isListening) return;
    await _speech.cancel();
    _setListening(false);
  }

  // ─── Lifecycle ───────────────────────────────────────────────────────────

  Future<void> dispose() async {
    _continuousMode = false;
    _restartScheduled = false;
    await stopListening();
    _isInitialized = false;
  }

  // ─── Command mapping ─────────────────────────────────────────────────────

  static VoiceCommand mapToCommand(String text) {
    final String lower = text.toLowerCase().trim();

    if (lower.contains('emergency') ||
        lower.contains('sos') ||
        lower.contains('help me')) {
      return VoiceCommand.sos;
    }
    if (lower.contains('stop') ||
        lower.contains('quiet') ||
        lower.contains('cancel')) {
      return VoiceCommand.stop;
    }
    if (lower.startsWith('navigate to') ||
        lower.startsWith('take me to') ||
        lower.startsWith('directions to') ||
        lower.startsWith('walk to') ||
        lower.startsWith('go to') ||
        lower.startsWith('route to')) {
      return VoiceCommand.navigateTo;
    }
    if (lower.startsWith('call ') ||
        lower.startsWith('phone ') ||
        lower.startsWith('dial ') ||
        lower.startsWith('ring ')) {
      return VoiceCommand.callContact;
    }
    if (lower.contains('scan qr') ||
        lower.contains('scan code') ||
        lower.contains('qr code') ||
        lower.contains('upi') ||
        lower.contains('payment') ||
        lower.contains('pay')) {
      return VoiceCommand.scanPayment;
    }
    if (lower.contains('who is there') ||
        lower.contains('who\'s there') ||
        lower.contains('anyone there') ||
        lower.contains('people') ||
        lower.contains('faces') ||
        lower.contains('person') ||
        lower.contains('someone')) {
      return VoiceCommand.detectPeople;
    }
    if (lower.contains('offline mode') ||
        lower.contains('on device') ||
        lower.contains('local model') ||
        lower.contains('on-device') ||
        lower.contains('switch to local') ||
        lower.contains('switch to cloud')) {
      return VoiceCommand.toggleOnDevice;
    }
    if (lower.contains('repeat') ||
        lower.contains('say again') ||
        lower.contains('what was that') ||
        lower.contains('current step')) {
      return VoiceCommand.repeatDirection;
    }
    if (lower.contains('where am i') ||
        lower.contains('how far') ||
        lower.contains('status') ||
        lower.contains('remaining') ||
        lower.contains('eta')) {
      return VoiceCommand.whereAmI;
    }
    if (lower.contains('currency') ||
        lower.contains('money') ||
        lower.contains('rupee') ||
        lower.contains('cash') ||
        lower.contains('denomination') ||
        lower.contains('bill') ||
        lower.contains('note')) {
      return VoiceCommand.identifyCurrency;
    }
    if (lower.contains('brightness') ||
        lower.contains('lights on') ||
        lower.contains('lights off') ||
        lower.contains('how bright') ||
        lower.contains('light') ||
        lower.contains('dark')) {
      return VoiceCommand.checkBrightness;
    }
    if (lower.contains('weather') ||
        lower.contains('temperature') ||
        lower.contains('rain') ||
        lower.contains('forecast') ||
        lower.contains('cold outside') ||
        lower.contains('hot')) {
      return VoiceCommand.checkWeather;
    }
    if (lower.contains('describe') ||
        lower.contains('what do you see') ||
        lower.contains('tell me about') ||
        lower.contains('scene') ||
        lower.contains('surroundings') ||
        lower.contains('around me') ||
        lower.contains('look')) {
      return VoiceCommand.describeScene;
    }
    if (lower.contains('navigate') ||
        lower.contains('navigation') ||
        lower.contains('guide me') ||
        lower.contains('walk')) {
      return VoiceCommand.navigation;
    }
    if (lower.contains('identify') ||
        lower.contains('what is') ||
        lower.contains('what are') ||
        lower.contains('what\'s in front') ||
        lower.contains('what is in front') ||
        lower.contains('what can i see') ||
        lower.contains('what do i see') ||
        lower.contains("what's around") ||
        lower.contains('find object') ||
        lower.contains('detect')) {
      return VoiceCommand.identifyObjects;
    }
    if (lower.contains('read') ||
        lower.contains('text') ||
        lower.contains('scan')) {
      return VoiceCommand.readText;
    }
    if (lower.contains('help') || lower.contains('commands')) {
      return VoiceCommand.help;
    }
    return VoiceCommand.unknown;
  }

  static String extractDestination(String rawText) {
    final String lower = rawText.toLowerCase().trim();
    for (final String prefix in <String>[
      'navigate to', 'take me to', 'directions to',
      'walk to', 'go to', 'route to',
    ]) {
      if (lower.startsWith(prefix)) {
        return rawText.substring(prefix.length).trim();
      }
    }
    return rawText;
  }

  static String extractContactName(String rawText) {
    final String lower = rawText.toLowerCase().trim();
    for (final String prefix in <String>[
      'call ', 'phone ', 'dial ', 'ring ',
    ]) {
      if (lower.startsWith(prefix)) {
        return rawText.substring(prefix.length).trim();
      }
    }
    return rawText;
  }

  static String get helpText =>
      'Available commands: '
      'Say "Read" to read text. '
      'Say "Identify" to find objects. '
      'Say "Navigate" to toggle obstacle detection. '
      'Say "Navigate to" followed by a place name for walking directions. '
      'Say "Repeat" to hear the current direction again. '
      'Say "Where am I" for navigation status. '
      'Say "Describe" for a scene description. '
      'Say "Pay" or "Scan QR" to scan a UPI payment code. '
      'Say "Money" or "Currency" to identify a banknote. '
      'Say "Light" or "Brightness" to check lighting conditions. '
      'Say "Weather" to hear the current weather. '
      'Say "Call" followed by a name to call a contact. '
      'Say "People" or "Who is there" to detect faces. '
      'Say "Offline mode" to toggle on-device A I. '
      'Say "Help" for this list. '
      'Say "Emergency" for SOS. '
      'Say "Stop" to cancel.';

  // ─── Internal ────────────────────────────────────────────────────────────

  void _setListening(bool value) {
    if (_isListening == value) return;
    _isListening = value;
    onListeningChanged?.call(value);
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!result.finalResult) return;

    _setListening(false);

    final String rawText = result.recognizedWords;
    if (rawText.trim().isEmpty) {
      _autoRestart();
      return;
    }

    final VoiceCommand command = mapToCommand(rawText);
    debugPrint('SttService: "$rawText" → $command');

    // Dispatch the command. The camera screen will call pauseForTts()
    // before speaking and the TTS completion callback calls resumeAfterTts().
    onCommand?.call(command, rawText);
  }

  void _onStatus(String status) {
    debugPrint('SttService status: $status');
    if (status == 'notListening' || status == 'done') {
      _setListening(false);
      _autoRestart();
    }
  }

  void _onError(dynamic error) {
    debugPrint('SttService error: $error');
    _setListening(false);
    _autoRestart();
  }

  /// Restarts listening in continuous mode, unless muted for TTS.
  void _autoRestart() {
    if (!_continuousMode || _mutedForTts) return;
    _scheduleRestart();
  }

  /// Debounced restart — only one pending restart at a time.
  void _scheduleRestart() {
    if (_restartScheduled) return;
    _restartScheduled = true;
    Future.delayed(const Duration(milliseconds: 500), () {
      _restartScheduled = false;
      if (_continuousMode && !_mutedForTts && !_isListening) {
        startListening();
      }
    });
  }
}
