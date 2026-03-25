import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';

import 'model_manager.dart';

/// On-device scene description service powered by SmolVLM2-2.2B.
///
/// Uses llamadart (llama.cpp via FFI) to run a quantized vision-language model
/// entirely on the phone. No network, no API keys, no latency.
///
/// The public API matches [GeminiService] so it can be used as a drop-in
/// replacement when on-device mode is enabled.
class OnDeviceVisionService {
  OnDeviceVisionService({required ModelManager modelManager})
      : _modelManager = modelManager;

  final ModelManager _modelManager;

  LlamaEngine? _engine;
  bool _isReady = false;
  bool _cancelled = false;

  /// Cached loading future to prevent concurrent loadModel() races.
  Future<bool>? _loadFuture;

  DateTime lastCallTime = DateTime(2000);

  bool get isReady => _isReady;
  bool get isLoading => _loadFuture != null;

  // ─── Prompts ────────────────────────────────────────────────────────────────

  static const String _scenePrompt =
      'You are an assistant for a visually impaired person. '
      'Describe what you see in this image in 2-3 clear, concise sentences. '
      'Focus on: what objects are present, their spatial arrangement, any text '
      'visible, and potential hazards or obstacles. '
      'Be specific about directions (left, right, ahead, behind). '
      'Use simple language that is easy to understand when spoken aloud.';

  static const String _currencyPrompt =
      'You are helping a visually impaired person identify currency. '
      'Look at this image and identify any banknotes or coins visible. '
      'State the denomination and currency clearly. '
      'If no currency is visible, say so briefly.';

  // ─── Lifecycle ──────────────────────────────────────────────────────────────

  /// Loads the SmolVLM2 model into memory. Safe to call concurrently —
  /// only one load operation runs at a time.
  Future<bool> loadModel() =>
      _loadFuture ??= _doLoadModel().whenComplete(() => _loadFuture = null);

  Future<bool> _doLoadModel() async {
    if (_isReady) return true;

    final ready =
        await _modelManager.isModelReady(OnDeviceModel.smolvlm2Vision);
    if (!ready) {
      debugPrint('SmolVLM2: model files not found or incomplete');
      // Check what's actually on disk for diagnostics
      final mPath =
          await _modelManager.modelPath(OnDeviceModel.smolvlm2Vision);
      final pPath =
          await _modelManager.projectorPath(OnDeviceModel.smolvlm2Vision);
      debugPrint('  Model path: $mPath exists=${File(mPath).existsSync()}');
      if (pPath != null) {
        debugPrint('  Projector path: $pPath exists=${File(pPath).existsSync()}');
      }
      return false;
    }

    try {
      final mPath =
          await _modelManager.modelPath(OnDeviceModel.smolvlm2Vision);
      final pPath =
          await _modelManager.projectorPath(OnDeviceModel.smolvlm2Vision);

      debugPrint('SmolVLM2: loading model from $mPath '
          '(${(File(mPath).lengthSync() / 1024 / 1024).toStringAsFixed(0)}MB)');

      _engine = LlamaEngine(LlamaBackend());
      await _engine!.loadModel(mPath);
      debugPrint('SmolVLM2: model loaded, loading projector...');

      // Load multimodal projector for vision
      if (pPath != null) {
        debugPrint('SmolVLM2: loading projector from $pPath '
            '(${(File(pPath).lengthSync() / 1024 / 1024).toStringAsFixed(0)}MB)');
        await _engine!.loadMultimodalProjector(pPath);
      }

      _isReady = true;
      debugPrint('SmolVLM2 vision model loaded successfully');
      return true;
    } catch (e, stack) {
      debugPrint('Failed to load SmolVLM2: $e');
      debugPrint('Stack: $stack');
      try {
        await _engine?.dispose();
      } catch (_) {}
      _engine = null;
      _isReady = false;
      return false;
    }
  }

  /// Unloads the model to free RAM.
  Future<void> unload() async {
    _cancelled = true;
    if (_engine != null) {
      await _engine!.dispose();
      _engine = null;
    }
    _isReady = false;
    _cancelled = false;
  }

  /// Cancels any in-progress inference.
  void cancelInference() {
    _cancelled = true;
  }

  // ─── Public API (matches GeminiService interface) ───────────────────────────

  /// Describes a scene from JPEG bytes. Returns a 2-3 sentence description.
  Future<String> describeScene(Uint8List jpegBytes) async {
    return _runVisionInference(jpegBytes, _scenePrompt);
  }

  /// Identifies currency from JPEG bytes.
  Future<String> identifyCurrency(Uint8List jpegBytes) async {
    return _runVisionInference(jpegBytes, _currencyPrompt);
  }

  /// Describes a scene from a file path.
  Future<String> describeSceneFromFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw OnDeviceModelException('Image file not found.');
    }
    return describeScene(await file.readAsBytes());
  }

  /// Runs a custom vision prompt against an image.
  Future<String> analyzeImage(Uint8List jpegBytes, String prompt) async {
    return _runVisionInference(jpegBytes, prompt);
  }

  // ─── Internal ───────────────────────────────────────────────────────────────

  Future<String> _runVisionInference(
      Uint8List jpegBytes, String prompt) async {
    if (!_isReady || _engine == null) {
      throw const OnDeviceModelException(
        'Vision model not loaded. Please download it in Settings.',
      );
    }

    _cancelled = false;

    try {
      // Save image to temp file for llamadart
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
          '${tempDir.path}/lumi_vision_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(jpegBytes);

      try {
        // Create a fresh session per inference to avoid KV cache accumulation
        final session = ChatSession(
          _engine!,
          systemPrompt:
              'You are a helpful assistant for visually impaired people. '
              'Always respond concisely in 2-3 sentences.',
        );

        final buffer = StringBuffer();
        await for (final chunk in session.create([
          LlamaImageContent(path: tempFile.path),
          LlamaTextContent(prompt),
        ])) {
          if (_cancelled) break;
          final content = chunk.choices.first.delta.content;
          if (content != null) buffer.write(content);
        }

        if (_cancelled) {
          throw const OnDeviceModelException('Inference cancelled.');
        }

        final result = buffer.toString().trim();
        if (result.isEmpty) {
          throw const OnDeviceModelException(
            'Model returned empty response. Try again.',
          );
        }

        lastCallTime = DateTime.now();
        return result;
      } finally {
        // Clean up temp file
        if (tempFile.existsSync()) await tempFile.delete();
      }
    } catch (e) {
      if (e is OnDeviceModelException) rethrow;
      debugPrint('Vision inference error: $e');
      throw OnDeviceModelException(
        'On-device vision failed: ${e.toString().split('\n').first}',
      );
    }
  }
}

/// Exception for on-device model errors with user-friendly messages.
class OnDeviceModelException implements Exception {
  const OnDeviceModelException(this.message);
  final String message;

  @override
  String toString() => 'OnDeviceModelException: $message';
}
