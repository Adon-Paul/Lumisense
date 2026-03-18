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
  Future<bool> init() async {
    if (_isInitialized) return _speech.isAvailable;

    try {
      final bool available = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
        debugLogging: kDebugMode,
      );
      _isInitialized = true;
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
  static VoiceCommand mapToCommand(String text) {
    final String lower = text.toLowerCase().trim();

    // Read / OCR
    if (lower.contains('read') || lower.contains('text') || lower.contains('scan')) {
      return VoiceCommand.readText;
    }

    // Identify / object detection
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

    // Navigation mode toggle
    if (lower.contains('navigate') ||
        lower.contains('navigation') ||
        lower.contains('guide me') ||
        lower.contains('walk')) {
      return VoiceCommand.navigation;
    }

    // Describe / scene description
    if (lower.contains('describe') ||
        lower.contains('what do you see') ||
        lower.contains('tell me about') ||
        lower.contains('explain') ||
        lower.contains('scene') ||
        lower.contains('surroundings') ||
        lower.contains('around me') ||
        lower.contains('look')) {
      return VoiceCommand.describeScene;
    }

    // Help
    if (lower.contains('help') || lower.contains('commands')) {
      return VoiceCommand.help;
    }

    // Emergency / SOS
    if (lower.contains('emergency') ||
        lower.contains('sos') ||
        lower.contains('help me')) {
      return VoiceCommand.sos;
    }

    // Stop
    if (lower.contains('stop') || lower.contains('quiet') || lower.contains('cancel')) {
      return VoiceCommand.stop;
    }

    return VoiceCommand.unknown;
  }

  /// Returns a help string listing available voice commands.
  static String get helpText =>
      'Available commands: '
      'Say "Read" to read text. '
      'Say "What\'s in front of me" or "Identify" to find objects. '
      'Say "Navigate" to toggle navigation mode. '
      'Say "Describe" or "Tell me about this" for a scene description. '
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
