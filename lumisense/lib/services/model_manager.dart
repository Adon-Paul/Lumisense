import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Manages downloading, caching, and lifecycle of on-device GGUF model files.
///
/// Models are stored in the app's documents directory (persistent across
/// restarts, cleared only on uninstall). Downloads are resumable via HTTP
/// Range headers, survive network interruptions with automatic retry, and
/// keep the screen awake to prevent the OS from killing the connection.
class ModelManager {
  ModelManager();

  final Dio _dio = Dio();

  /// Maximum number of automatic retries on transient network failures.
  static const int _maxRetries = 3;

  /// Delay between retry attempts (doubles each retry).
  static const Duration _baseRetryDelay = Duration(seconds: 3);

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
          'https://huggingface.co/ggml-org/SmolVLM2-2.2B-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-2.2B-Instruct-f16.gguf',
      modelFileName: 'smolvlm2-2.2b-q4km.gguf',
      projectorFileName: 'mmproj-smolvlm2-2.2b-f16.gguf',
      estimatedModelSizeMB: 1061,
      estimatedProjectorSizeMB: 832,
      estimatedRamMB: 3000,
      supportsVision: true,
      supportsFunctionCalling: false,
    ),
    OnDeviceModel.gemma3nAssistant: ModelInfo(
      id: 'gemma-3n-e2b',
      displayName: 'Gemma 3n E2B (Assistant)',
      description: 'Conversational AI with function calling',
      modelUrl:
          'https://huggingface.co/unsloth/gemma-3n-E2B-it-GGUF/resolve/main/gemma-3n-E2B-it-Q4_K_M.gguf',
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

  /// Last error message per model. Null if no error.
  final Map<OnDeviceModel, ValueNotifier<String?>> downloadError = {
    for (final model in OnDeviceModel.values)
      model: ValueNotifier<String?>(null),
  };

  /// Active cancel tokens for in-flight downloads.
  final Map<OnDeviceModel, CancelToken> _cancelTokens = {};

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

  /// Downloads model files with progress reporting, automatic retry on
  /// transient errors, and wakelock to prevent sleep mid-download.
  ///
  /// Partial files are preserved on failure so the next attempt resumes
  /// from where it left off.
  Future<void> downloadModel(OnDeviceModel model) async {
    final info = models[model]!;
    final dir = Directory(await _modelsDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final cancelToken = CancelToken();
    _cancelTokens[model] = cancelToken;
    downloadError[model]!.value = null;

    // Keep screen on so the OS doesn't kill our download
    bool wakelockWasEnabled = false;
    try {
      wakelockWasEnabled = await WakelockPlus.enabled;
      if (!wakelockWasEnabled) {
        await WakelockPlus.enable();
      }
    } catch (e) {
      debugPrint('ModelManager: wakelock enable failed (non-fatal): $e');
    }

    try {
      final int totalParts = info.projectorUrl != null ? 2 : 1;
      int completedParts = 0;

      // Download main model
      downloadProgress[model]!.value = 0.0;
      await _downloadFileWithRetry(
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
        await _downloadFileWithRetry(
          url: info.projectorUrl!,
          savePath: (await projectorPath(model))!,
          cancelToken: cancelToken,
          onProgress: (progress) {
            downloadProgress[model]!.value =
                (completedParts + progress) / totalParts;
          },
        );
      }

      downloadProgress[model]!.value = null; // Done — success
    } on DioException catch (e) {
      downloadProgress[model]!.value = null;
      if (e.type == DioExceptionType.cancel) {
        debugPrint('Download cancelled for ${info.displayName}');
        // Don't delete partial files on cancel — they enable resume
      } else {
        downloadError[model]!.value = _friendlyErrorMessage(e);
        rethrow;
      }
    } on DownloadException catch (e) {
      downloadProgress[model]!.value = null;
      downloadError[model]!.value = e.message;
      rethrow;
    } catch (e) {
      downloadProgress[model]!.value = null;
      downloadError[model]!.value = 'Unexpected error: $e';
      rethrow;
    } finally {
      _cancelTokens.remove(model);
      // Restore wakelock to previous state
      try {
        if (!wakelockWasEnabled) {
          await WakelockPlus.disable();
        }
      } catch (_) {}
    }
  }

  /// Cancel an in-flight download. Partial files are kept for resume.
  void cancelDownload(OnDeviceModel model) {
    _cancelTokens[model]?.cancel('User cancelled');
  }

  /// Delete downloaded model files to free storage.
  Future<void> deleteModel(OnDeviceModel model) async {
    downloadError[model]!.value = null;
    await _deleteFile(await modelPath(model));
    final pPath = await projectorPath(model);
    if (pPath != null) await _deleteFile(pPath);
  }

  // ─── Internal: retry wrapper ───────────────────────────────────────────────

  /// Wraps [_downloadFileResumable] with automatic retry on transient errors.
  Future<void> _downloadFileWithRetry({
    required String url,
    required String savePath,
    required CancelToken cancelToken,
    required void Function(double progress) onProgress,
  }) async {
    int attempt = 0;

    while (true) {
      try {
        await _downloadFileResumable(
          url: url,
          savePath: savePath,
          cancelToken: cancelToken,
          onProgress: onProgress,
        );
        return; // Success
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;

        attempt++;
        final bool isRetryable = _isRetryableError(e);

        if (!isRetryable || attempt >= _maxRetries) {
          debugPrint('Download failed after $attempt attempts: '
              '${e.type} ${e.response?.statusCode} ${e.message}');
          rethrow;
        }

        // Exponential backoff: 3s, 6s, 12s
        final delay = _baseRetryDelay * (1 << (attempt - 1));
        debugPrint('Download attempt $attempt failed (${e.type}), '
            'retrying in ${delay.inSeconds}s...');
        await Future.delayed(delay);
        // Loop continues — _downloadFileResumable will pick up partial file
      }
    }
  }

  /// Returns true for errors that are worth retrying (network issues, timeouts,
  /// server errors) vs permanent failures (404, 403).
  bool _isRetryableError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        // Retry on 5xx (server errors), 429 (rate limited)
        // Don't retry on 4xx (client errors like 404, 403)
        return code >= 500 || code == 429;
      default:
        return false;
    }
  }

  // ─── Internal: resumable download ──────────────────────────────────────────

  /// Downloads a file with resume support via HTTP Range headers.
  ///
  /// If a partial file exists at [savePath], sends a Range header to resume
  /// from where it left off. The partial data is streamed and **appended**
  /// to the existing file (not overwritten).
  Future<void> _downloadFileResumable({
    required String url,
    required String savePath,
    required CancelToken cancelToken,
    required void Function(double progress) onProgress,
  }) async {
    final partialFile = File(savePath);
    int existingBytes = 0;

    if (partialFile.existsSync()) {
      existingBytes = partialFile.lengthSync();
    }

    // HEAD request to get total size and check range support
    int totalBytes = 0;
    bool supportsRanges = false;
    try {
      final headResponse = await _dio.head<void>(
        url,
        options: Options(
          followRedirects: true,
          maxRedirects: 5,
          receiveTimeout: const Duration(seconds: 30),
        ),
        cancelToken: cancelToken,
      );
      final contentLength = headResponse.headers.value('content-length');
      if (contentLength != null) {
        totalBytes = int.tryParse(contentLength) ?? 0;
      }
      final acceptRanges = headResponse.headers.value('accept-ranges');
      supportsRanges = acceptRanges != null && acceptRanges != 'none';
    } catch (_) {
      // HEAD failed — proceed without knowing total size
    }

    // If file already complete, skip download
    if (totalBytes > 0 && existingBytes >= totalBytes) {
      onProgress(1.0);
      return;
    }

    // Resume via Range header + streaming append
    if (existingBytes > 0 && totalBytes > 0 && supportsRanges) {
      try {
        final response = await _dio.get<ResponseBody>(
          url,
          cancelToken: cancelToken,
          options: Options(
            followRedirects: true,
            maxRedirects: 5,
            receiveTimeout: const Duration(minutes: 30),
            responseType: ResponseType.stream,
            headers: {'Range': 'bytes=$existingBytes-'},
          ),
        );

        final statusCode = response.statusCode ?? 0;
        if (statusCode == 206) {
          // Server returned partial content — append to file
          final sink = partialFile.openWrite(mode: FileMode.append);
          int receivedSoFar = 0;
          try {
            await for (final chunk in response.data!.stream) {
              sink.add(chunk);
              receivedSoFar += chunk.length;
              final totalReceived = existingBytes + receivedSoFar;
              onProgress(totalReceived / totalBytes);
            }
          } finally {
            await sink.flush();
            await sink.close();
          }
          return;
        }

        // Server returned 200 instead of 206 — it doesn't support our range.
        // Fall through to full download.
        debugPrint('Server returned $statusCode instead of 206, '
            'restarting download');
        if (partialFile.existsSync()) await partialFile.delete();
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;
        final code = e.response?.statusCode ?? 0;
        if (code == 416) {
          // Range not satisfiable — partial file is likely corrupt
          debugPrint('416 Range Not Satisfiable, restarting download');
          if (partialFile.existsSync()) await partialFile.delete();
        } else {
          rethrow; // Let retry wrapper handle it
        }
      }
    }

    // Full download (no resume) — stream to file
    final response = await _dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        followRedirects: true,
        maxRedirects: 5,
        receiveTimeout: const Duration(minutes: 30),
        responseType: ResponseType.stream,
      ),
    );

    final contentLength = response.headers.value('content-length');
    final fullSize =
        contentLength != null ? int.tryParse(contentLength) ?? 0 : totalBytes;

    final sink = partialFile.openWrite(mode: FileMode.write);
    int received = 0;
    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (fullSize > 0) {
          onProgress(received / fullSize);
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  /// Produces a user-friendly error message from a Dio exception.
  static String _friendlyErrorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Check your internet and try again.';
      case DioExceptionType.connectionError:
        return 'No internet connection. Connect to Wi-Fi and try again.';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        if (code == 404) return 'Model file not found on server (404).';
        if (code == 403) return 'Access denied by server (403).';
        if (code == 429) return 'Too many requests. Wait a moment and retry.';
        if (code >= 500) return 'Server error ($code). Try again later.';
        return 'Download failed with status $code.';
      case DioExceptionType.cancel:
        return 'Download was cancelled.';
      default:
        return 'Download failed: ${e.message ?? 'unknown error'}';
    }
  }

  Future<void> _deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  void dispose() {
    for (final notifier in downloadProgress.values) {
      notifier.dispose();
    }
    for (final notifier in downloadError.values) {
      notifier.dispose();
    }
    _dio.close();
  }
}

// ─── Exceptions ──────────────────────────────────────────────────────────────

class DownloadException implements Exception {
  final String message;
  const DownloadException(this.message);
  @override
  String toString() => 'DownloadException: $message';
}

// ─── Enums & Models ──────────────────────────────────────────────────────────

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
