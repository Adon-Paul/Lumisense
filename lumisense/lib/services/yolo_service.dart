import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_vision/flutter_vision.dart';

/// Result from a single YOLO detection pass.
class YoloDetection {
  const YoloDetection({
    required this.label,
    required this.confidence,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  final String label;
  final double confidence;

  /// Bounding box coordinates relative to the camera image size.
  final double x1;
  final double y1;
  final double x2;
  final double y2;
}

/// Wraps [FlutterVision] for YOLOv8 object detection.
///
/// Handles model loading, frame inference, and GPU delegate configuration.
/// The native layer handles YUV420→RGB conversion and NMS internally.
class YoloService {
  YoloService._internal();
  static final YoloService _instance = YoloService._internal();
  factory YoloService() => _instance;

  FlutterVision? _vision;
  bool _isModelLoaded = false;
  bool _isDisposed = false;

  /// Whether the YOLO model has been loaded and is ready for inference.
  bool get isReady => _isModelLoaded && !_isDisposed;

  // ─── Model loading ──────────────────────────────────────────────────────────

  /// Loads the YOLOv8n model from assets.
  ///
  /// [useGpu] enables the GPU delegate for faster inference on supported
  /// devices (Adreno, Mali, etc). Falls back to CPU if GPU fails.
  /// [numThreads] controls CPU thread count (only used when GPU is off).
  Future<void> loadModel({
    String modelPath = 'assets/models/yolov8n.tflite',
    String labelsPath = 'assets/labels.txt',
    bool useGpu = true,
    int numThreads = 2,
  }) async {
    if (_isModelLoaded) return;
    _isDisposed = false;

    _vision = FlutterVision();

    try {
      await _vision!.loadYoloModel(
        labels: labelsPath,
        modelPath: modelPath,
        modelVersion: 'yolov8',
        quantization: false,
        numThreads: numThreads,
        useGpu: useGpu,
      );
      _isModelLoaded = true;
      debugPrint('YoloService: Model loaded (GPU=$useGpu, threads=$numThreads)');
    } catch (e) {
      // GPU delegate can fail on some devices — retry with CPU.
      if (useGpu) {
        debugPrint('YoloService: GPU delegate failed ($e), retrying with CPU...');
        try {
          await _vision!.loadYoloModel(
            labels: labelsPath,
            modelPath: modelPath,
            modelVersion: 'yolov8',
            quantization: false,
            numThreads: numThreads,
            useGpu: false,
          );
          _isModelLoaded = true;
          debugPrint('YoloService: Model loaded (CPU fallback, threads=$numThreads)');
        } catch (e2) {
          debugPrint('YoloService: CPU fallback also failed: $e2');
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  // ─── Inference ──────────────────────────────────────────────────────────────

  /// Runs YOLO detection on a camera frame from [startImageStream].
  ///
  /// Returns a list of [YoloDetection] objects sorted by confidence (descending).
  /// The bounding box coordinates are relative to the camera image dimensions.
  ///
  /// [confThreshold] filters low-confidence detections (0.0–1.0).
  /// [iouThreshold] controls NMS overlap merging (0.0–1.0).
  Future<List<YoloDetection>> detectOnFrame(
    CameraImage image, {
    double confThreshold = 0.45,
    double iouThreshold = 0.45,
    double classThreshold = 0.50,
  }) async {
    if (!isReady) return const [];

    try {
      final List<Map<String, dynamic>> results = await _vision!.yoloOnFrame(
        bytesList: image.planes.map((Plane plane) => plane.bytes).toList(),
        imageHeight: image.height,
        imageWidth: image.width,
        iouThreshold: iouThreshold,
        confThreshold: confThreshold,
        classThreshold: classThreshold,
      );

      if (results.isEmpty) return const [];

      final List<YoloDetection> detections = <YoloDetection>[];
      for (final Map<String, dynamic> result in results) {
        final List<dynamic> box = result['box'] as List<dynamic>;
        final String tag = result['tag'] as String;

        detections.add(YoloDetection(
          label: tag,
          confidence: (box[4] as num).toDouble(),
          x1: (box[0] as num).toDouble(),
          y1: (box[1] as num).toDouble(),
          x2: (box[2] as num).toDouble(),
          y2: (box[3] as num).toDouble(),
        ));
      }

      // Sort by confidence descending.
      detections.sort(
        (YoloDetection a, YoloDetection b) =>
            b.confidence.compareTo(a.confidence),
      );

      return detections;
    } catch (e) {
      debugPrint('YoloService: detectOnFrame error: $e');
      return const [];
    }
  }

  // ─── Lifecycle ──────────────────────────────────────────────────────────────

  /// Releases the model and native resources.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _isModelLoaded = false;
    try {
      await _vision?.closeYoloModel();
    } catch (e) {
      debugPrint('YoloService: dispose error: $e');
    }
    _vision = null;
  }
}
