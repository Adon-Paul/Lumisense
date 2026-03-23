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

  /// Whether on-device mode is enabled in settings.
  bool get isEnabled => _modelManager.useOnDeviceModels;

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

  /// Ensures the vision model is loaded. Returns true if ready.
  ///
  /// If RAM is limited, this will unload the assistant model first.
  Future<bool> ensureVisionReady({bool unloadAssistant = false}) async {
    if (visionService.isReady) return true;

    // Free RAM if requested
    if (unloadAssistant && assistantService.isReady) {
      debugPrint('Unloading assistant model to free RAM for vision...');
      await assistantService.unload();
    }

    return visionService.loadModel();
  }

  /// Ensures the assistant model is loaded. Returns true if ready.
  ///
  /// If RAM is limited, this will unload the vision model first.
  Future<bool> ensureAssistantReady({bool unloadVision = false}) async {
    if (assistantService.isReady) return true;

    if (unloadVision && visionService.isReady) {
      debugPrint('Unloading vision model to free RAM for assistant...');
      await visionService.unload();
    }

    return assistantService.loadModel();
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

  // ─── Cleanup ────────────────────────────────────────────────────────────────

  /// Unloads all models to free memory.
  Future<void> unloadAll() async {
    await Future.wait([
      visionService.unload(),
      assistantService.unload(),
    ]);
  }

  void dispose() {
    visionService.unload();
    assistantService.unload();
    _modelManager.dispose();
  }
}
