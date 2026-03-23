import 'package:flutter/material.dart';
import 'package:lumisense/utils/theme.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

// ─── Color palette for bounding boxes ────────────────────────────────────────

const List<Color> _boxColors = [
  Color(0xFFFF3B30), // red
  Color(0xFF34C759), // green
  Color(0xFF007AFF), // blue
  Color(0xFFFF9500), // orange
  Color(0xFFAF52DE), // purple
  Color(0xFFFFCC00), // yellow
  Color(0xFF5AC8FA), // teal
  Color(0xFFFF2D55), // pink
  Color(0xFF30D158), // mint
  Color(0xFF5856D6), // indigo
];

/// Renders bounding boxes over the camera preview using [normalizedBox]
/// coordinates (0.0–1.0) from [YOLOResult].
///
/// This is a Flutter-side overlay that works regardless of whether the
/// native plugin renders its own overlays.
class BoundingBoxOverlay extends StatelessWidget {
  const BoundingBoxOverlay({
    super.key,
    required this.detections,
    required this.previewSize,
  });

  final List<YOLOResult> detections;
  final Size previewSize;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: previewSize,
      painter: _BoundingBoxPainter(detections: detections),
    );
  }
}

class _BoundingBoxPainter extends CustomPainter {
  _BoundingBoxPainter({required this.detections});

  final List<YOLOResult> detections;

  @override
  void paint(Canvas canvas, Size size) {
    for (final YOLOResult det in detections) {
      final Color color = _boxColors[det.classIndex % _boxColors.length];
      final Rect norm = det.normalizedBox;

      // Map normalized coordinates (0–1) to pixel coordinates.
      final Rect box = Rect.fromLTRB(
        norm.left * size.width,
        norm.top * size.height,
        norm.right * size.width,
        norm.bottom * size.height,
      );

      // Draw bounding box.
      final Paint boxPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRect(box, boxPaint);

      // Draw label background.
      final String label =
          '${det.className} ${(det.confidence * 100).toStringAsFixed(0)}%';
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final double labelW = tp.width + 8;
      final double labelH = tp.height + 4;

      // Position label above the box if space, else inside top.
      final double labelY =
          box.top > labelH + 2 ? box.top - labelH - 2 : box.top + 2;

      final RRect labelBg = RRect.fromRectAndRadius(
        Rect.fromLTWH(box.left, labelY, labelW, labelH),
        const Radius.circular(4),
      );
      canvas.drawRRect(labelBg, Paint()..color = color);

      tp.paint(canvas, Offset(box.left + 4, labelY + 2));
    }
  }

  @override
  bool shouldRepaint(_BoundingBoxPainter oldDelegate) =>
      !identical(oldDelegate.detections, detections);
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
