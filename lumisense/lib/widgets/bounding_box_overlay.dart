import 'package:flutter/material.dart';
import 'package:lumisense/services/yolo_service.dart';
import 'package:lumisense/utils/theme.dart';

/// Renders YOLO bounding boxes on top of the camera preview.
///
/// Coordinates from [YoloDetection] are in camera-image space and must be
/// scaled to the preview widget size. On Android the camera sensor is
/// landscape-oriented but the preview is portrait, so we swap width/height
/// when computing scale factors.
class BoundingBoxOverlay extends StatelessWidget {
  const BoundingBoxOverlay({
    super.key,
    required this.detections,
    required this.previewSize,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<YoloDetection> detections;

  /// The size of the camera preview widget on screen.
  final Size previewSize;

  /// The raw camera image width (from [CameraImage.width]).
  final int imageWidth;

  /// The raw camera image height (from [CameraImage.height]).
  final int imageHeight;

  // ─── Color palette for detected classes ──────────────────────────────────

  static const List<Color> _palette = [
    Color(0xFF4CAF50), // green
    Color(0xFF2196F3), // blue
    Color(0xFFFF9800), // orange
    Color(0xFFE91E63), // pink
    Color(0xFF9C27B0), // purple
    Color(0xFF00BCD4), // cyan
    Color(0xFF00BFFF), // electric blue
    Color(0xFFFF5722), // deep orange
    Color(0xFF3F51B5), // indigo
    Color(0xFF8BC34A), // light green
  ];

  Color _colorForLabel(String label) {
    return _palette[label.hashCode.abs() % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    if (detections.isEmpty) return const SizedBox.shrink();

    // On Android the camera sensor is rotated 90 from the display.
    // Camera image dimensions: width is the short side, height is the long side
    // when held in portrait. flutter_vision returns boxes in camera-image space.
    //
    // Scale factors map camera coordinates → preview widget coordinates.
    final double factorX = previewSize.width / (imageHeight > 0 ? imageHeight : 1);
    final double factorY = previewSize.height / (imageWidth > 0 ? imageWidth : 1);

    return Stack(
      children: detections.map((YoloDetection det) {
        final Color color = _colorForLabel(det.label);
        final double left = det.x1 * factorX;
        final double top = det.y1 * factorY;
        final double width = (det.x2 - det.x1) * factorX;
        final double height = (det.y2 - det.y1) * factorY;

        return Positioned(
          left: left.clamp(0, previewSize.width),
          top: top.clamp(0, previewSize.height),
          width: width.clamp(0, previewSize.width - left.clamp(0, previewSize.width)),
          height: height.clamp(0, previewSize.height - top.clamp(0, previewSize.height)),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 2.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.85),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomRight: Radius.circular(6),
                  ),
                ),
                child: Text(
                  '${det.label} ${(det.confidence * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Indicator shown when navigation mode is active.
class NavigationModeIndicator extends StatelessWidget {
  const NavigationModeIndicator({
    super.key,
    required this.isActive,
    required this.detectionCount,
    required this.fps,
  });

  final bool isActive;
  final int detectionCount;
  final double fps;

  @override
  Widget build(BuildContext context) {
    if (!isActive) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.navigation, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(
            'NAV ${fps.toStringAsFixed(0)}fps',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
          if (detectionCount > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$detectionCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
