// ignore_for_file: depend_on_referenced_packages
/// Generates the LumiSense app icon assets.
///
/// Run from project root:
///   dart run tool/generate_icon.dart
///
/// Produces:
///   assets/icon/icon.png           — 1024x1024 full icon
///   assets/icon/icon_foreground.png — 432x432 adaptive foreground
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

void main() {
  print('Generating LumiSense app icons...');

  // ── Full icon (1024x1024) ──────────────────────────────────────────────────
  final img.Image full = _createIcon(1024);
  final Uint8List fullPng = Uint8List.fromList(img.encodePng(full));
  File('assets/icon/icon.png').writeAsBytesSync(fullPng);
  print('  ✓ assets/icon/icon.png (1024x1024)');

  // ── Adaptive foreground (432x432) ──────────────────────────────────────────
  final img.Image fg = _createForeground(432);
  final Uint8List fgPng = Uint8List.fromList(img.encodePng(fg));
  File('assets/icon/icon_foreground.png').writeAsBytesSync(fgPng);
  print('  ✓ assets/icon/icon_foreground.png (432x432)');

  print('Done!');
}

/// Creates a full app icon with dark background and electric blue eye symbol.
img.Image _createIcon(int size) {
  final img.Image image = img.Image(width: size, height: size);

  // Dark background (#121212)
  final img.Color bgColor = img.ColorRgba8(0x12, 0x12, 0x12, 0xFF);
  img.fill(image, color: bgColor);

  // Rounded rectangle background
  final int radius = (size * 0.18).round();
  _drawRoundedRect(image, 0, 0, size, size, radius, bgColor);

  // Draw the eye/lightbulb symbol in electric blue
  _drawLumiSenseSymbol(image, size);

  return image;
}

/// Creates the adaptive icon foreground (transparent background, just the symbol).
img.Image _createForeground(int size) {
  final img.Image image = img.Image(width: size, height: size);

  // Transparent background
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));

  // Draw the eye/lightbulb symbol in electric blue
  _drawLumiSenseSymbol(image, size);

  return image;
}

/// Draws the LumiSense symbol — a stylized eye with a light beam.
/// Represents vision + illumination.
void _drawLumiSenseSymbol(img.Image image, int size) {
  final img.Color blue = img.ColorRgba8(0x00, 0xBF, 0xFF, 0xFF);
  final img.Color white = img.ColorRgba8(0xFF, 0xFF, 0xFF, 0xFF);
  final img.Color lightBlue = img.ColorRgba8(0x00, 0xBF, 0xFF, 0x80);

  final double cx = size / 2;
  final double cy = size / 2;
  final double r = size * 0.28; // main circle radius

  // ── Outer glow ring ──────────────────────────────────────────────────────
  _drawCircleOutline(image, cx, cy, r * 1.15, r * 1.22, lightBlue);

  // ── Main circle (eye/lens) ───────────────────────────────────────────────
  _drawFilledCircle(image, cx, cy, r, blue);

  // ── Inner highlight (pupil) ──────────────────────────────────────────────
  _drawFilledCircle(image, cx, cy, r * 0.38, img.ColorRgba8(0x12, 0x12, 0x12, 0xFF));
  _drawFilledCircle(image, cx - r * 0.08, cy - r * 0.08, r * 0.15, white);

  // ── Light rays radiating outward ─────────────────────────────────────────
  const int numRays = 8;
  final double rayInner = r * 1.30;
  final double rayOuter = r * 1.55;

  for (int i = 0; i < numRays; i++) {
    final double angle = (i * 2 * math.pi / numRays) - math.pi / 2;
    final double x1 = cx + rayInner * math.cos(angle);
    final double y1 = cy + rayInner * math.sin(angle);
    final double x2 = cx + rayOuter * math.cos(angle);
    final double y2 = cy + rayOuter * math.sin(angle);
    _drawThickLine(image, x1, y1, x2, y2, (size * 0.02).round().clamp(2, 8), blue);
  }
}

void _drawFilledCircle(img.Image image, double cx, double cy, double radius, img.Color color) {
  final int r2 = (radius * radius).round();
  for (int y = (cy - radius).round(); y <= (cy + radius).round(); y++) {
    for (int x = (cx - radius).round(); x <= (cx + radius).round(); x++) {
      final double dx = x - cx;
      final double dy = y - cy;
      if (dx * dx + dy * dy <= r2) {
        if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
          image.setPixel(x, y, color);
        }
      }
    }
  }
}

void _drawCircleOutline(
    img.Image image, double cx, double cy, double innerR, double outerR, img.Color color) {
  final int ir2 = (innerR * innerR).round();
  final int or2 = (outerR * outerR).round();
  for (int y = (cy - outerR).round(); y <= (cy + outerR).round(); y++) {
    for (int x = (cx - outerR).round(); x <= (cx + outerR).round(); x++) {
      final double dx = x - cx;
      final double dy = y - cy;
      final double d2 = dx * dx + dy * dy;
      if (d2 >= ir2 && d2 <= or2) {
        if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
          image.setPixel(x, y, color);
        }
      }
    }
  }
}

void _drawThickLine(
    img.Image image, double x1, double y1, double x2, double y2, int thickness, img.Color color) {
  final int steps = ((x2 - x1).abs() + (y2 - y1).abs()).round().clamp(1, 9999);
  final int halfT = thickness ~/ 2;
  for (int i = 0; i <= steps; i++) {
    final double t = i / steps;
    final int px = (x1 + (x2 - x1) * t).round();
    final int py = (y1 + (y2 - y1) * t).round();
    for (int dy = -halfT; dy <= halfT; dy++) {
      for (int dx = -halfT; dx <= halfT; dx++) {
        final int fx = px + dx;
        final int fy = py + dy;
        if (fx >= 0 && fx < image.width && fy >= 0 && fy < image.height) {
          image.setPixel(fx, fy, color);
        }
      }
    }
  }
}

void _drawRoundedRect(
    img.Image image, int left, int top, int width, int height, int radius, img.Color color) {
  // Just fill — the icon generators handle masking to shape
  img.fill(image, color: color);
}
