import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Result of face detection, formatted for TTS output.
class FaceDetectionResult {
  const FaceDetectionResult({
    required this.faceCount,
    required this.description,
    required this.processingTimeMs,
  });

  final int faceCount;
  final String description;
  final int processingTimeMs;
}

/// Detects faces in camera images using Google ML Kit (on-device, no API key).
///
/// Returns a TTS-friendly description of faces found, including count,
/// position, expression (smiling), and eye state.
class FaceDetectionService {
  FaceDetectionService()
      : _detector = FaceDetector(
          options: FaceDetectorOptions(
            enableClassification: true, // smiling, eyes open probability
            enableLandmarks: true, // eye, nose, mouth positions
            enableTracking: true, // track faces across frames
            performanceMode: FaceDetectorMode.accurate,
          ),
        );

  final FaceDetector _detector;
  bool _isDisposed = false;

  /// Detects faces from an image file path and returns a TTS-friendly result.
  Future<FaceDetectionResult> detectFromFile(String imagePath) async {
    if (_isDisposed) {
      throw StateError('FaceDetectionService has been disposed.');
    }

    final Stopwatch sw = Stopwatch()..start();

    final InputImage inputImage = InputImage.fromFilePath(imagePath);
    final List<Face> faces = await _detector.processImage(inputImage);

    sw.stop();

    if (faces.isEmpty) {
      return FaceDetectionResult(
        faceCount: 0,
        description: 'No faces detected. There does not appear to be anyone '
            'in front of you.',
        processingTimeMs: sw.elapsedMilliseconds,
      );
    }

    final String description = _buildDescription(faces);
    return FaceDetectionResult(
      faceCount: faces.length,
      description: description,
      processingTimeMs: sw.elapsedMilliseconds,
    );
  }

  String _buildDescription(List<Face> faces) {
    if (faces.length == 1) {
      return 'I see 1 person. ${_describeFace(faces.first, null)}';
    }

    final StringBuffer sb = StringBuffer();
    sb.write('I see ${faces.length} people. ');

    // Sort faces left-to-right by bounding box center X.
    final List<Face> sorted = List<Face>.from(faces)
      ..sort((Face a, Face b) =>
          a.boundingBox.center.dx.compareTo(b.boundingBox.center.dx));

    for (int i = 0; i < sorted.length; i++) {
      final String position = _horizontalPosition(
          sorted[i], sorted.length, i);
      sb.write('Person ${i + 1} $position. ');
      sb.write(_describeFace(sorted[i], position));
      if (i < sorted.length - 1) sb.write(' ');
    }

    return sb.toString().trim();
  }

  String _describeFace(Face face, String? positionAlreadyMentioned) {
    final List<String> traits = <String>[];

    // Smiling
    final double? smile = face.smilingProbability;
    if (smile != null) {
      if (smile > 0.7) {
        traits.add('smiling');
      } else if (smile > 0.3) {
        traits.add('has a neutral expression');
      }
    }

    // Eyes
    final double? leftEye = face.leftEyeOpenProbability;
    final double? rightEye = face.rightEyeOpenProbability;
    if (leftEye != null && rightEye != null) {
      if (leftEye < 0.3 && rightEye < 0.3) {
        traits.add('eyes appear closed');
      }
    }

    // Head rotation — facing toward or away
    final double? rotY = face.headEulerAngleY; // left-right rotation
    if (rotY != null) {
      if (rotY.abs() < 15) {
        traits.add('facing you directly');
      } else if (rotY > 30) {
        traits.add('looking to their left');
      } else if (rotY < -30) {
        traits.add('looking to their right');
      }
    }

    // Approximate distance from face size (bigger box = closer)
    final double faceWidth = face.boundingBox.width;
    if (faceWidth > 250) {
      traits.add('very close');
    } else if (faceWidth > 150) {
      traits.add('at arm\'s length');
    } else if (faceWidth < 80) {
      traits.add('further away');
    }

    if (traits.isEmpty) return '';
    return 'They are ${traits.join(', ')}.';
  }

  String _horizontalPosition(Face face, int total, int index) {
    if (total <= 1) return '';
    final double fraction = index / (total - 1);
    if (fraction < 0.33) return 'on your left';
    if (fraction > 0.66) return 'on your right';
    return 'in the center';
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _detector.close();
  }
}
