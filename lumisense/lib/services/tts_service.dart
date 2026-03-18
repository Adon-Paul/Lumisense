import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Singleton wrapper around [FlutterTts].
///
/// All voice output in LumiSense must go through this service so queue
/// handling, speech-rate updates, and platform quirks stay consistent.
///
/// Usage:
/// ```dart
/// await TtsService().init();
/// await TtsService().speak('Hello, world!');
/// ```
class TtsService {
  TtsService._internal();

  static final TtsService _instance = TtsService._internal();

  factory TtsService() => _instance;

  // ─── Internal state ────────────────────────────────────────────────────────

  final FlutterTts _tts = FlutterTts();

  bool _isInitialized = false;
  bool _isSpeaking = false;

  double _speechRate = 0.5;
  double _volume = 1.0;
  double _pitch = 1.0;

  /// In-flight init future — used for concurrent-caller deduplication.
  /// Nulled on failure to allow a subsequent retry.
  Future<void>? _initFuture;

  // ─── Completion callbacks ───────────────────────────────────────────────────

  /// Called when a [speak] call finishes naturally.
  VoidCallback? onSpeakComplete;

  /// Called when speech is cancelled (e.g., [stop] was called mid-speech).
  VoidCallback? onSpeakCancel;

  /// Called when the TTS engine reports an error.
  ValueChanged<String>? onSpeakError;

  // ─── Public getters ─────────────────────────────────────────────────────────

  bool get isInitialized => _isInitialized;
  bool get isSpeaking => _isSpeaking;
  double get speechRate => _speechRate;
  double get volume => _volume;
  double get pitch => _pitch;

  // ─── Initialization ─────────────────────────────────────────────────────────

  /// Initialises the TTS engine. Safe to call multiple times — concurrent
  /// callers share the same in-flight future. On failure the future is cleared
  /// so the next call can retry.
  Future<void> init() {
    if (_isInitialized) return Future.value();
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    try {
      // ── Platform-specific audio session setup ──────────────────────────────
      if (Platform.isIOS) {
        // Without this, TTS produces no sound on real iOS devices.
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          ],
          IosTextToSpeechAudioMode.voicePrompt,
        );
      }

      // ── Language with en-IN → en-US fallback ───────────────────────────────
      final Object? langAvailable =
          await _tts.isLanguageAvailable('en-IN');
      final String language =
          langAvailable == 1 ? 'en-IN' : 'en-US';
      await _tts.setLanguage(language);

      // ── Engine defaults ────────────────────────────────────────────────────
      await _tts.setSpeechRate(_speechRate);
      await _tts.setVolume(_volume);
      await _tts.setPitch(_pitch);

      // Explicit flush mode (0 = replace current speech; 1 = enqueue).
      await _tts.setQueueMode(0);

      // NOTE: awaitSpeakCompletion(true) is intentionally NOT set globally.
      // Doing so combined with stop() causes NullPointerException crashes on
      // Android (flutter_tts issue #217). Completion is tracked via callbacks.

      // ── Register persistent callbacks ─────────────────────────────────────
      _tts.setStartHandler(() {
        _isSpeaking = true;
      });

      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        onSpeakComplete?.call();
      });

      _tts.setCancelHandler(() {
        _isSpeaking = false;
        onSpeakCancel?.call();
      });

      _tts.setErrorHandler((dynamic message) {
        _isSpeaking = false;
        onSpeakError?.call(message?.toString() ?? 'TTS error');
      });

      _isInitialized = true;
    } catch (e) {
      // Allow retry on next call.
      _initFuture = null;
      rethrow;
    }
  }

  // ─── Speech control ─────────────────────────────────────────────────────────

  /// Speaks [text]. Any ongoing speech is stopped first.
  ///
  /// Returns silently if [text] is blank. Throws if the TTS engine rejects
  /// the call (result != 1).
  Future<void> speak(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await init();

    // Only call stop() when actually speaking to avoid unnecessary
    // round-trips to the native engine (saves ~5 ms on Android).
    if (_isSpeaking) {
      await _tts.stop();
    }

    final Object? result = await _tts.speak(trimmed);
    if (result != 1) {
      debugPrint('TtsService: speak() returned $result for: "$trimmed"');
    }
  }

  /// Stops any ongoing speech immediately.
  Future<void> stop() async {
    if (!_isInitialized) return;
    await _tts.stop();
  }

  // ─── Settings ───────────────────────────────────────────────────────────────

  /// Updates speech rate in range [0.0, 1.0] and applies it to the engine.
  Future<void> setSpeechRate(double value) async {
    final double clamped = value.clamp(0.0, 1.0);
    if (_speechRate == clamped) return;
    _speechRate = clamped;
    await init();
    await _tts.setSpeechRate(clamped);
  }

  /// Updates volume in range [0.0, 1.0] and applies it to the engine.
  Future<void> setVolume(double value) async {
    final double clamped = value.clamp(0.0, 1.0);
    if (_volume == clamped) return;
    _volume = clamped;
    await init();
    await _tts.setVolume(clamped);
  }

  /// Updates pitch in range [0.5, 2.0] and applies it to the engine.
  Future<void> setPitch(double value) async {
    final double clamped = value.clamp(0.5, 2.0);
    if (_pitch == clamped) return;
    _pitch = clamped;
    await init();
    await _tts.setPitch(clamped);
  }

  // ─── Lifecycle ──────────────────────────────────────────────────────────────

  /// Stops speech and releases the engine reference.
  ///
  /// After calling [dispose] the singleton can be re-initialised by calling
  /// [init] again.
  Future<void> dispose() async {
    if (!_isInitialized) return;
    await _tts.stop();
    _isInitialized = false;
    _isSpeaking = false;
    _initFuture = null;
  }
}
