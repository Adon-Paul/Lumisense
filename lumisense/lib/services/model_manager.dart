import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages downloading, caching, and lifecycle of on-device GGUF model files.
///
/// Models are stored in the app's documents directory (persistent across
/// restarts, cleared only on uninstall). Downloads are resumable and report
/// progress via a [ValueNotifier].
class ModelManager {
  ModelManager({required SharedPreferences prefs}) : _prefs = prefs;

  final SharedPreferences _prefs;
  final Dio _dio = Dio();

  // ─── Model Definitions ──────────────────────────────────────────────────────

  /// Available on-device models.
  static const Map<OnDeviceModel, ModelInfo> models = {
    OnDeviceModel.smolvlm2Vision: ModelInfo(
      id: 'smolvlm2-2.2b',
      displayName: 'SmolVLM2 2.2B (Vision)',
      description: 'On-device scene description & image understanding',
      modelUrl:
          'https://huggingface.co/ggml-org/SmolVLM2-2.2B-Instruct-GGUF/resolve/main/SmolVLM2-2.2B-Instruct-Q4_K_M.gguf',
      projectorUrl:
          'https://huggingface.co/ggml-org/SmolVLM2-2.2B-Instruct-GGUF/resolve/main/SmolVLM2-2.2B-Instruct-mmproj-f16.gguf',
      modelFileName: 'smolvlm2-2.2b-q4km.gguf',
      projectorFileName: 'smolvlm2-2.2b-mmproj-f16.gguf',
      estimatedModelSizeMB: 1400,
      estimatedProjectorSizeMB: 800,
      estimatedRamMB: 3000,
      supportsVision: true,
      supportsFunctionCalling: false,
    ),
    OnDeviceModel.gemma3nAssistant: ModelInfo(
      id: 'gemma-3n-e2b',
      displayName: 'Gemma 3n E2B (Assistant)',
      description: 'Conversational AI with function calling',
      modelUrl:
          'https://huggingface.co/ggml-org/gemma-3n-E2B-it-GGUF/resolve/main/gemma-3n-E2B-it-Q4_K_M.gguf',
      projectorUrl: null,
      modelFileName: 'gemma-3n-e2b-q4km.gguf',
      projectorFileName: null,
      estimatedModelSizeMB: 2800,
      estimatedProjectorSizeMB: 0,
      estimatedRamMB: 4000,
      supportsVision: false,
      supportsFunctionCalling: true,
    ),
  };

  // ─── Download State ─────────────────────────────────────────────────────────

  /// Current download progress per model (0.0–1.0). Null if not downloading.
  final Map<OnDeviceModel, ValueNotifier<double?>> downloadProgress = {
    for (final model in OnDeviceModel.values)
      model: ValueNotifier<double?>(null),
  };

  /// Active cancel tokens for in-flight downloads.
  final Map<OnDeviceModel, CancelToken> _cancelTokens = {};

  // ─── Prefs Keys ─────────────────────────────────────────────────────────────

  static const String _kUseOnDevice = 'useOnDeviceModels';

  bool get useOnDeviceModels => _prefs.getBool(_kUseOnDevice) ?? false;

  Future<void> setUseOnDeviceModels(bool value) async {
    await _prefs.setBool(_kUseOnDevice, value);
  }

  // ─── Paths ──────────────────────────────────────────────────────────────────

  Future<String> get _modelsDir async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/lumisense_models';
  }

  Future<String> modelPath(OnDeviceModel model) async {
    final info = models[model]!;
    return '${await _modelsDir}/${info.modelFileName}';
  }

  Future<String?> projectorPath(OnDeviceModel model) async {
    final info = models[model]!;
    if (info.projectorFileName == null) return null;
    return '${await _modelsDir}/${info.projectorFileName}';
  }

  // ─── Status ─────────────────────────────────────────────────────────────────

  /// Checks whether the model (and its projector, if any) are fully downloaded.
  Future<bool> isModelReady(OnDeviceModel model) async {
    final info = models[model]!;
    final mPath = await modelPath(model);
    if (!File(mPath).existsSync()) return false;

    if (info.projectorFileName != null) {
      final pPath = await projectorPath(model);
      if (pPath == null || !File(pPath).existsSync()) return false;
    }
    return true;
  }

  /// Returns model file size in MB, or 0 if not downloaded.
  Future<double> modelSizeMB(OnDeviceModel model) async {
    final mPath = await modelPath(model);
    final file = File(mPath);
    if (!file.existsSync()) return 0;
    double total = file.lengthSync() / (1024 * 1024);

    final pPath = await projectorPath(model);
    if (pPath != null) {
      final pFile = File(pPath);
      if (pFile.existsSync()) {
        total += pFile.lengthSync() / (1024 * 1024);
      }
    }
    return total;
  }

  // ─── Download ───────────────────────────────────────────────────────────────

  /// Downloads model files with progress reporting. Resumes partial downloads.
  Future<void> downloadModel(OnDeviceModel model) async {
    final info = models[model]!;
    final dir = Directory(await _modelsDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final cancelToken = CancelToken();
    _cancelTokens[model] = cancelToken;

    try {
      // Calculate total bytes to download for combined progress.
      final int totalParts = info.projectorUrl != null ? 2 : 1;
      int completedParts = 0;

      // Download main model
      downloadProgress[model]!.value = 0.0;
      await _downloadFile(
        url: info.modelUrl,
        savePath: await modelPath(model),
        cancelToken: cancelToken,
        onProgress: (progress) {
          downloadProgress[model]!.value =
              (completedParts + progress) / totalParts;
        },
      );
      completedParts = 1;

      // Download projector if needed
      if (info.projectorUrl != null) {
        await _downloadFile(
          url: info.projectorUrl!,
          savePath: (await projectorPath(model))!,
          cancelToken: cancelToken,
          onProgress: (progress) {
            downloadProgress[model]!.value =
                (completedParts + progress) / totalParts;
          },
        );
      }

      downloadProgress[model]!.value = null; // Done
    } on DioException catch (e) {
      downloadProgress[model]!.value = null;
      if (e.type == DioExceptionType.cancel) {
        debugPrint('Download cancelled for ${info.displayName}');
        // Clean up partial files
        await _deleteFile(await modelPath(model));
        if (info.projectorFileName != null) {
          await _deleteFile((await projectorPath(model))!);
        }
      } else {
        rethrow;
      }
    } finally {
      _cancelTokens.remove(model);
    }
  }

  /// Cancel an in-flight download.
  void cancelDownload(OnDeviceModel model) {
    _cancelTokens[model]?.cancel('User cancelled');
  }

  /// Delete downloaded model files to free storage.
  Future<void> deleteModel(OnDeviceModel model) async {
    await _deleteFile(await modelPath(model));
    final pPath = await projectorPath(model);
    if (pPath != null) await _deleteFile(pPath);
  }

  // ─── Internal ───────────────────────────────────────────────────────────────

  Future<void> _downloadFile({
    required String url,
    required String savePath,
    required CancelToken cancelToken,
    required void Function(double progress) onProgress,
  }) async {
    await _dio.download(
      url,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress(received / total);
        }
      },
      options: Options(
        // Follow redirects (HuggingFace uses CDN redirects)
        followRedirects: true,
        maxRedirects: 5,
        receiveTimeout: const Duration(minutes: 30),
      ),
    );
  }

  Future<void> _deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  void dispose() {
    for (final notifier in downloadProgress.values) {
      notifier.dispose();
    }
    _dio.close();
  }
}

// ─── Enums & Models ───────────────────────────────────────────────────────────

/// Identifiers for available on-device models.
enum OnDeviceModel {
  smolvlm2Vision,
  gemma3nAssistant,
}

/// Static metadata about a downloadable model.
class ModelInfo {
  const ModelInfo({
    required this.id,
    required this.displayName,
    required this.description,
    required this.modelUrl,
    required this.projectorUrl,
    required this.modelFileName,
    required this.projectorFileName,
    required this.estimatedModelSizeMB,
    required this.estimatedProjectorSizeMB,
    required this.estimatedRamMB,
    required this.supportsVision,
    required this.supportsFunctionCalling,
  });

  final String id;
  final String displayName;
  final String description;
  final String modelUrl;
  final String? projectorUrl;
  final String modelFileName;
  final String? projectorFileName;
  final int estimatedModelSizeMB;
  final int estimatedProjectorSizeMB;
  final int estimatedRamMB;
  final bool supportsVision;
  final bool supportsFunctionCalling;

  /// Total estimated download size in MB.
  int get estimatedTotalSizeMB =>
      estimatedModelSizeMB + estimatedProjectorSizeMB;
}
