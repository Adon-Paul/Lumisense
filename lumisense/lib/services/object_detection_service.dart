import 'dart:math';

import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:lumisense/models/detection_result.dart';

class ObjectDetectionService {
  ObjectDetectionService()
      : _detector = ObjectDetector(
          options: ObjectDetectorOptions(
            mode: DetectionMode.single,
            classifyObjects: true,
            multipleObjects: true,
          ),
        );

  final ObjectDetector _detector;
  bool _isDisposed = false;

  Future<DetectionResult> detectFromImagePath(String imagePath) async {
    if (_isDisposed) {
      throw StateError('Object detection service has been disposed.');
    }

    final Stopwatch stopwatch = Stopwatch()..start();

    final InputImage image = InputImage.fromFilePath(imagePath);
    final List<DetectedObject> detectedObjects =
        await _detector.processImage(image);

    final List<DetectedObjectItem> results = <DetectedObjectItem>[];
    final Set<String> seenLabels = <String>{};

    for (final DetectedObject object in detectedObjects) {
      final List<Label> labels = object.labels;
      if (labels.isEmpty) {
        continue;
      }

      labels.sort((a, b) => b.confidence.compareTo(a.confidence));
      final Label top = labels.first;
      final String normalized = top.text.trim().toLowerCase();
      if (normalized.isEmpty || seenLabels.contains(normalized)) {
        continue;
      }

      seenLabels.add(normalized);
      results.add(
        DetectedObjectItem(
          label: top.text.trim(),
          confidence: top.confidence,
        ),
      );
    }

    results.sort((a, b) => b.confidence.compareTo(a.confidence));

    stopwatch.stop();

    return DetectionResult(
      items: results,
      processingTimeMs: max(0, stopwatch.elapsedMilliseconds),
    );
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _detector.close();
  }
}
