import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Result of a brightness analysis.
class BrightnessResult {
  const BrightnessResult({
    required this.averageLuminance,
    required this.label,
    required this.description,
  });

  /// Average luminance on a 0–255 scale.
  final double averageLuminance;

  /// Human-readable label (e.g. "Dark", "Bright").
  final String label;

  /// TTS-friendly description of the lighting conditions.
  final String description;
}

/// Analyses camera frames to determine ambient brightness/lighting.
///
/// No ML needed — pure pixel luminance calculation using ITU-R BT.709.
class BrightnessDetectorService {
  const BrightnessDetectorService();

  /// Threshold boundaries (on 0–255 luminance scale).
  static const double _darkThreshold = 30;
  static const double _dimThreshold = 80;
  static const double _moderateThreshold = 150;
  static const double _brightThreshold = 210;

  /// Analyses a JPEG/PNG image and returns a [BrightnessResult].
  ///
  /// Samples every [sampleStep]th pixel for speed.
  BrightnessResult analyseFromBytes(Uint8List imageBytes, {int sampleStep = 8}) {
    final img.Image? image = img.decodeImage(imageBytes);
    if (image == null) {
      return const BrightnessResult(
        averageLuminance: 0,
        label: 'Unknown',
        description: 'Could not analyse the image. Please try again.',
      );
    }

    double totalLuminance = 0;
    int sampleCount = 0;

    for (int y = 0; y < image.height; y += sampleStep) {
      for (int x = 0; x < image.width; x += sampleStep) {
        final img.Pixel pixel = image.getPixel(x, y);
        // ITU-R BT.709 luminance formula (values already 0–255).
        final double lum =
            0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b;
        totalLuminance += lum;
        sampleCount++;
      }
    }

    if (sampleCount == 0) {
      return const BrightnessResult(
        averageLuminance: 0,
        label: 'Unknown',
        description: 'Could not analyse the image. Please try again.',
      );
    }

    final double avg = totalLuminance / sampleCount;
    return _classify(avg);
  }

  BrightnessResult _classify(double avgLum) {
    if (avgLum < _darkThreshold) {
      return BrightnessResult(
        averageLuminance: avgLum,
        label: 'Dark',
        description:
            'It is very dark. The lights appear to be off, or you may be in a dark room. '
            'Luminance level: ${avgLum.round()} out of 255.',
      );
    }
    if (avgLum < _dimThreshold) {
      return BrightnessResult(
        averageLuminance: avgLum,
        label: 'Dim',
        description:
            'The lighting is dim. There is some light but it is quite low. '
            'This could be dusk, a poorly lit room, or ambient lighting. '
            'Luminance level: ${avgLum.round()} out of 255.',
      );
    }
    if (avgLum < _moderateThreshold) {
      return BrightnessResult(
        averageLuminance: avgLum,
        label: 'Moderate',
        description:
            'The lighting is moderate. This is typical indoor lighting. '
            'The lights are on and the room is reasonably well-lit. '
            'Luminance level: ${avgLum.round()} out of 255.',
      );
    }
    if (avgLum < _brightThreshold) {
      return BrightnessResult(
        averageLuminance: avgLum,
        label: 'Bright',
        description:
            'It is bright. You are likely in a well-lit area or near a window '
            'with daylight. Luminance level: ${avgLum.round()} out of 255.',
      );
    }
    return BrightnessResult(
      averageLuminance: avgLum,
      label: 'Very Bright',
      description:
          'It is very bright. You may be outdoors in direct sunlight '
          'or under very strong lighting. '
          'Luminance level: ${avgLum.round()} out of 255.',
    );
  }
}
