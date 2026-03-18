// Legacy ObjectDetectionService — replaced by YoloService for real-time
// detection with 80 COCO classes. This file is kept for backward compatibility
// but is no longer used in the camera screen.
//
// See lib/services/yolo_service.dart for the current implementation.

import 'package:lumisense/models/detection_result.dart';

/// Stub for the old ML Kit object detection service.
///
/// All object detection now goes through [YoloService] which provides:
/// - 80 COCO class labels (vs ML Kit's 5 coarse categories)
/// - Real-time bounding boxes for navigation mode
/// - GPU-accelerated inference via TFLite
@Deprecated('Use YoloService instead')
class ObjectDetectionService {
  bool _isDisposed = false;

  Future<DetectionResult> detectFromImagePath(String imagePath) async {
    if (_isDisposed) {
      throw StateError('Object detection service has been disposed.');
    }
    // Return empty result — callers should migrate to YoloService.
    return const DetectionResult(items: [], processingTimeMs: 0);
  }

  Future<void> dispose() async {
    _isDisposed = true;
  }
}
