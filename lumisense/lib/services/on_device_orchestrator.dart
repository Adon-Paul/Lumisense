import 'package:flutter/foundation.dart';

import 'model_manager.dart';
import 'on_device_assistant_service.dart';
import 'on_device_vision_service.dart';

/// Orchestrates the dual on-device model stack.
///
/// Routes tasks to the appropriate model:
/// - **SmolVLM2** for vision tasks (scene description, currency ID, image Q&A)
/// - **Gemma 3n E2B** for conversation and function calling
///
/// Models are loaded on demand and can be swapped — only one needs to be
/// in memory at a time if RAM is tight, or both can coexist on 6-7 GB devices.
class OnDeviceOrchestrator {
  OnDeviceOrchestrator({required ModelManager modelManager})
      : _modelManager = modelManager,
        visionService = OnDeviceVisionService(modelManager: modelManager),
        assistantService =
            OnDeviceAssistantService(modelManager: modelManager);

  final ModelManager _modelManager;
  final OnDeviceVisionService visionService;
  final OnDeviceAssistantService assistantService;

  // ─── Model Readiness ────────────────────────────────────────────────────────

  /// True if the vision model is downloaded and ready to load.
  Future<bool> get isVisionModelReady =>
      _modelManager.isModelReady(OnDeviceModel.smolvlm2Vision);

  /// True if the assistant model is downloaded and ready to load.
  Future<bool> get isAssistantModelReady =>
      _modelManager.isModelReady(OnDeviceModel.gemma3nAssistant);

  /// True if at least one model is available for on-device use.
  Future<bool> get hasAnyModel async {
    return await isVisionModelReady || await isAssistantModelReady;
  }

  // ─── Smart Loading ──────────────────────────────────────────────────────────

  /// Ensures the vision model is loaded and ready for inference.
  ///
  /// Throws [OnDeviceModelException] if the model can't be loaded.
  Future<void> ensureVisionReady({bool unloadAssistant = false}) async {
    if (visionService.isReady) return;

    // Free RAM if requested
    if (unloadAssistant && assistantService.isReady) {
      debugPrint('Unloading assistant model to free RAM for vision...');
      await assistantService.unload();
    }

    final loaded = await visionService.loadModel();
    if (!loaded) {
      // Diagnose why loading failed
      final downloaded =
          await _modelManager.isModelReady(OnDeviceModel.smolvlm2Vision);
      if (!downloaded) {
        throw const OnDeviceModelException(
          'Vision model not downloaded. Please download SmolVLM2 in Settings.',
        );
      }
      throw const OnDeviceModelException(
        'Vision model failed to load. The file may be corrupt — '
        'try deleting and re-downloading it in Settings.',
      );
    }
  }

  /// Ensures the assistant model is loaded and ready for inference.
  ///
  /// Throws [OnDeviceModelException] if the model can't be loaded.
  Future<void> ensureAssistantReady({bool unloadVision = false}) async {
    if (assistantService.isReady) return;

    if (unloadVision && visionService.isReady) {
      debugPrint('Unloading vision model to free RAM for assistant...');
      await visionService.unload();
    }

    final loaded = await assistantService.loadModel();
    if (!loaded) {
      final downloaded =
          await _modelManager.isModelReady(OnDeviceModel.gemma3nAssistant);
      if (!downloaded) {
        throw const OnDeviceModelException(
          'Assistant model not downloaded. Please download Gemma 3n in Settings.',
        );
      }
      throw const OnDeviceModelException(
        'Assistant model failed to load. The file may be corrupt — '
        'try deleting and re-downloading it in Settings.',
      );
    }
  }

  // ─── High-Level API ─────────────────────────────────────────────────────────

  /// Describes a scene using the on-device vision model.
  ///
  /// Throws [OnDeviceModelException] if the model is not available.
  Future<String> describeScene(Uint8List jpegBytes) async {
    await ensureVisionReady();
    return visionService.describeScene(jpegBytes);
  }

  /// Identifies currency using the on-device vision model.
  Future<String> identifyCurrency(Uint8List jpegBytes) async {
    await ensureVisionReady();
    return visionService.identifyCurrency(jpegBytes);
  }

  /// Analyzes an image with a custom prompt.
  Future<String> analyzeImage(Uint8List jpegBytes, String prompt) async {
    await ensureVisionReady();
    return visionService.analyzeImage(jpegBytes, prompt);
  }

  /// Processes a conversational message through the assistant.
  ///
  /// Returns an [AssistantResponse] that may contain text, an app action,
  /// or both. The caller is responsible for executing any actions.
  Future<AssistantResponse> chat(String message) async {
    await ensureAssistantReady();
    return assistantService.processMessage(message);
  }

  /// Resets the assistant's conversation context.
  void resetConversation() {
    assistantService.resetConversation();
  }

  // ─── Cancellation ─────────────────────────────────────────────────────────

  /// Cancels all in-progress inference operations.
  void cancelAll() {
    visionService.cancelInference();
    assistantService.cancelInference();
  }

  // ─── Cleanup ────────────────────────────────────────────────────────────────

  /// Unloads all models to free memory.
  Future<void> unloadAll() async {
    await Future.wait([
      visionService.unload(),
      assistantService.unload(),
    ]);
  }

  /// Disposes all resources. Awaits model unloading to prevent native leaks.
  Future<void> dispose() async {
    await visionService.unload();
    await assistantService.unload();
  }
}
