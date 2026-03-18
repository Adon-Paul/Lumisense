class DetectedObjectItem {
  const DetectedObjectItem({
    required this.label,
    required this.confidence,
  });

  final String label;
  final double confidence;
}

class DetectionResult {
  const DetectionResult({
    required this.items,
    required this.processingTimeMs,
  });

  final List<DetectedObjectItem> items;
  final int processingTimeMs;

  bool get hasObjects => items.isNotEmpty;
}
