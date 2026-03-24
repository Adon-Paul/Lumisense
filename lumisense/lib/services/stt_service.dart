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
typedef OnVoiceCommandCallback = void Function(VoiceCommand command, String rawText);

/// Wraps [SpeechToText] to provide push-to-talk voice command recognition.
///
/// Maps recognised phrases to [VoiceCommand] values and invokes [onCommand].
///
/// Usage:
/// ```dart
/// final stt = SttService();
/// await stt.init();
/// stt.onCommand = (cmd, raw) => print('$cmd from "$raw"');
/// await stt.startListening();
/// ```
class SttService {
  SttService();

  final SpeechToText _speech = SpeechToText();

  bool _isInitialized = false;
  bool _isListening = false;

  /// Called when a final voice command is recognised.
  OnVoiceCommandCallback? onCommand;

  /// Called when the listening status changes (started / stopped).
  ValueChanged<bool>? onListeningChanged;

  // ─── Public getters ──────────────────────────────────────────────────────

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  bool get isAvailable => _isInitialized && _speech.isAvailable;

  // ─── Initialization ──────────────────────────────────────────────────────

  /// Initialises the speech recogniser. Returns `true` if the engine and
  /// microphone permission are available.
  /// Initialises the speech recogniser. Returns `true` if the engine and
  /// microphone permission are available. Safe to call multiple times —
  /// retries on failure (does not cache a failed init).
  Future<bool> init() async {
    if (_isInitialized) return _speech.isAvailable;

    try {
      final bool available = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
        debugLogging: kDebugMode,
      );
      // Only mark as initialised on success so callers can retry.
      if (available) {
        _isInitialized = true;
      }
      return available;
    } catch (e) {
      debugPrint('SttService init failed: $e');
      return false;
    }
  }

  // ─── Listening control ───────────────────────────────────────────────────

  /// Starts a single listening session. Automatically stops after a pause.
  ///
  /// Call [init] first. If the engine is unavailable this is a no-op.
  Future<void> startListening() async {
    if (!_isInitialized || !_speech.isAvailable) {
      debugPrint('SttService: cannot start — not initialised or unavailable.');
      return;
    }

    if (_isListening) return;

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

    _isListening = true;
    onListeningChanged?.call(true);
  }

  /// Stops the current listening session.
  Future<void> stopListening() async {
    if (!_isListening) return;
    await _speech.stop();
    _isListening = false;
    onListeningChanged?.call(false);
  }

  /// Cancels listening without processing the last result.
  Future<void> cancelListening() async {
    if (!_isListening) return;
    await _speech.cancel();
    _isListening = false;
    onListeningChanged?.call(false);
  }

  // ─── Lifecycle ───────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await stopListening();
    // SpeechToText does not have a dispose method.
    _isInitialized = false;
  }

  // ─── Command mapping ─────────────────────────────────────────────────────

  /// Maps raw recognised text to a [VoiceCommand].
  ///
  /// Commands are ordered from most specific to least specific to prevent
  /// false matches. Multi-word phrases are checked before single keywords.
  static VoiceCommand mapToCommand(String text) {
    final String lower = text.toLowerCase().trim();

    // ── 1. Emergency / SOS (highest priority — safety first) ────────────
    if (lower.contains('emergency') ||
        lower.contains('sos') ||
        lower.contains('help me')) {
      return VoiceCommand.sos;
    }

    // ── 2. Stop (second highest — user wants to cancel) ─────────────────
    if (lower.contains('stop') || lower.contains('quiet') || lower.contains('cancel')) {
      return VoiceCommand.stop;
    }

    // ── 3. Turn-by-turn navigation (startsWith — before generic "navigate")
    if (lower.startsWith('navigate to') ||
        lower.startsWith('take me to') ||
        lower.startsWith('directions to') ||
        lower.startsWith('walk to') ||
        lower.startsWith('go to') ||
        lower.startsWith('route to')) {
      return VoiceCommand.navigateTo;
    }

    // ── 4. Call contact (startsWith — "call mom", before generic keywords)
    if (lower.startsWith('call ') ||
        lower.startsWith('phone ') ||
        lower.startsWith('dial ') ||
        lower.startsWith('ring ')) {
      return VoiceCommand.callContact;
    }

    // ── 5. QR / Payment (before generic "scan" which would match readText)
    if (lower.contains('scan qr') ||
        lower.contains('scan code') ||
        lower.contains('qr code') ||
        lower.contains('upi') ||
        lower.contains('payment') ||
        lower.contains('pay')) {
      return VoiceCommand.scanPayment;
    }

    // ── 6. People detection (before generic "detect" / "who")
    if (lower.contains('who is there') ||
        lower.contains('who\'s there') ||
        lower.contains('anyone there') ||
        lower.contains('people') ||
        lower.contains('faces') ||
        lower.contains('person') ||
        lower.contains('someone')) {
      return VoiceCommand.detectPeople;
    }

    // ── 7. On-device AI toggle (multi-word phrases)
    if (lower.contains('offline mode') ||
        lower.contains('on device') ||
        lower.contains('local model') ||
        lower.contains('on-device') ||
        lower.contains('switch to local') ||
        lower.contains('switch to cloud')) {
      return VoiceCommand.toggleOnDevice;
    }

    // ── 8. Repeat current direction
    if (lower.contains('repeat') ||
        lower.contains('say again') ||
        lower.contains('what was that') ||
        lower.contains('current step')) {
      return VoiceCommand.repeatDirection;
    }

    // ── 9. Where am I / status
    if (lower.contains('where am i') ||
        lower.contains('how far') ||
        lower.contains('status') ||
        lower.contains('remaining') ||
        lower.contains('eta')) {
      return VoiceCommand.whereAmI;
    }

    // ── 10. Currency identification
    if (lower.contains('currency') ||
        lower.contains('money') ||
        lower.contains('rupee') ||
        lower.contains('cash') ||
        lower.contains('denomination') ||
        lower.contains('bill') ||
        lower.contains('note')) {
      return VoiceCommand.identifyCurrency;
    }

    // ── 11. Brightness / light detection
    if (lower.contains('brightness') ||
        lower.contains('lights on') ||
        lower.contains('lights off') ||
        lower.contains('how bright') ||
        lower.contains('light') ||
        lower.contains('dark')) {
      return VoiceCommand.checkBrightness;
    }

    // ── 12. Weather check
    if (lower.contains('weather') ||
        lower.contains('temperature') ||
        lower.contains('rain') ||
        lower.contains('forecast') ||
        lower.contains('cold outside') ||
        lower.contains('hot')) {
      return VoiceCommand.checkWeather;
    }

    // ── 13. Describe / scene description
    if (lower.contains('describe') ||
        lower.contains('what do you see') ||
        lower.contains('tell me about') ||
        lower.contains('scene') ||
        lower.contains('surroundings') ||
        lower.contains('around me') ||
        lower.contains('look')) {
      return VoiceCommand.describeScene;
    }

    // ── 14. Navigation mode toggle (generic "navigate", "walk")
    if (lower.contains('navigate') ||
        lower.contains('navigation') ||
        lower.contains('guide me') ||
        lower.contains('walk')) {
      return VoiceCommand.navigation;
    }

    // ── 15. Identify objects (generic "detect", "what is", "identify")
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

    // ── 16. Read / OCR (generic "read", "text", "scan" — most ambiguous)
    if (lower.contains('read') || lower.contains('text') || lower.contains('scan')) {
      return VoiceCommand.readText;
    }

    // ── 17. Help (generic — after SOS to prevent "help me" false match)
    if (lower.contains('help') || lower.contains('commands')) {
      return VoiceCommand.help;
    }

    return VoiceCommand.unknown;
  }

  /// Returns a help string listing available voice commands.
  /// Extracts the destination from a "navigate to X" voice command.
  static String extractDestination(String rawText) {
    final String lower = rawText.toLowerCase().trim();
    for (final String prefix in <String>[
      'navigate to',
      'take me to',
      'directions to',
      'walk to',
      'go to',
      'route to',
    ]) {
      if (lower.startsWith(prefix)) {
        return rawText.substring(prefix.length).trim();
      }
    }
    return rawText;
  }

  /// Extracts the contact name from a "call [name]" voice command.
  static String extractContactName(String rawText) {
    final String lower = rawText.toLowerCase().trim();
    for (final String prefix in <String>[
      'call ',
      'phone ',
      'dial ',
      'ring ',
    ]) {
      if (lower.startsWith(prefix)) {
        return rawText.substring(prefix.length).trim();
      }
    }
    return rawText;
  }

  /// Returns a help string listing available voice commands.
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

  // ─── Internal callbacks ──────────────────────────────────────────────────

  void _onResult(SpeechRecognitionResult result) {
    if (!result.finalResult) return;

    _isListening = false;
    onListeningChanged?.call(false);

    final String rawText = result.recognizedWords;
    if (rawText.trim().isEmpty) return;

    final VoiceCommand command = mapToCommand(rawText);
    debugPrint('SttService: recognised "$rawText" → $command');
    onCommand?.call(command, rawText);
  }

  void _onStatus(String status) {
    debugPrint('SttService status: $status');
    if (status == 'notListening' || status == 'done') {
      _isListening = false;
      onListeningChanged?.call(false);
    }
  }

  void _onError(dynamic error) {
    debugPrint('SttService error: $error');
    _isListening = false;
    onListeningChanged?.call(false);
  }
}
