/// A single detected object with optional bounding box.
class DetectedObjectItem {
  const DetectedObjectItem({
    required this.label,
    required this.confidence,
    this.x1,
    this.y1,
    this.x2,
    this.y2,
  });

  final String label;
  final double confidence;

  /// Bounding box coordinates (null for legacy ML Kit results).
  final double? x1;
  final double? y1;
  final double? x2;
  final double? y2;

  bool get hasBoundingBox => x1 != null && y1 != null && x2 != null && y2 != null;
}

/// Container for a batch of detection results.
class DetectionResult {
  const DetectionResult({
    required this.items,
    required this.processingTimeMs,
  });

  final List<DetectedObjectItem> items;
  final int processingTimeMs;

  bool get hasObjects => items.isNotEmpty;
}
