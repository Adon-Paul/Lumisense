import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Result of pose detection, formatted for TTS output.
class PoseDetectionResult {
  const PoseDetectionResult({
    required this.poseCount,
    required this.description,
    required this.processingTimeMs,
  });

  final int poseCount;
  final String description;
  final int processingTimeMs;
}

/// Detects human body poses in camera images using Google ML Kit (on-device).
///
/// Analyses 33 body landmarks to determine posture (standing, sitting,
/// arms raised) and describes them in a TTS-friendly format for blind users.
class PoseDetectionService {
  PoseDetectionService()
      : _detector = PoseDetector(
          options: PoseDetectorOptions(
            mode: PoseDetectionMode.single, // accurate, single frame
          ),
        );

  final PoseDetector _detector;
  bool _isDisposed = false;

  /// Detects poses from an image file and returns a TTS-friendly result.
  Future<PoseDetectionResult> detectFromFile(String imagePath) async {
    if (_isDisposed) {
      throw StateError('PoseDetectionService has been disposed.');
    }

    final Stopwatch sw = Stopwatch()..start();

    final InputImage inputImage = InputImage.fromFilePath(imagePath);
    final List<Pose> poses = await _detector.processImage(inputImage);

    sw.stop();

    if (poses.isEmpty) {
      return PoseDetectionResult(
        poseCount: 0,
        description: 'No person detected in the frame.',
        processingTimeMs: sw.elapsedMilliseconds,
      );
    }

    final String description = _buildDescription(poses);
    return PoseDetectionResult(
      poseCount: poses.length,
      description: description,
      processingTimeMs: sw.elapsedMilliseconds,
    );
  }

  String _buildDescription(List<Pose> poses) {
    if (poses.length == 1) {
      return _describePose(poses.first, null);
    }

    final StringBuffer sb = StringBuffer();
    sb.write('I detect ${poses.length} people. ');
    for (int i = 0; i < poses.length; i++) {
      sb.write('Person ${i + 1}: ${_describePose(poses[i], i)}');
      if (i < poses.length - 1) sb.write(' ');
    }
    return sb.toString().trim();
  }

  String _describePose(Pose pose, int? index) {
    final List<String> traits = <String>[];

    // Determine posture: standing vs sitting
    final _Posture posture = _analyzePosture(pose);
    traits.add(posture.label);

    // Check arm positions
    final String? armGesture = _analyzeArms(pose);
    if (armGesture != null) traits.add(armGesture);

    // Approximate position in frame (left/center/right)
    final String? position = _horizontalPosition(pose);
    if (position != null) traits.add(position);

    final String prefix =
        index == null ? 'A person is detected. ' : '';
    return '$prefix${traits.join(', ')}.';
  }

  _Posture _analyzePosture(Pose pose) {
    final PoseLandmark? leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final PoseLandmark? rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final PoseLandmark? leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
    final PoseLandmark? rightKnee =
        pose.landmarks[PoseLandmarkType.rightKnee];
    final PoseLandmark? leftAnkle =
        pose.landmarks[PoseLandmarkType.leftAnkle];
    final PoseLandmark? rightAnkle =
        pose.landmarks[PoseLandmarkType.rightAnkle];

    // Need hips and knees to determine posture.
    if (leftHip == null ||
        rightHip == null ||
        leftKnee == null ||
        rightKnee == null) {
      return _Posture.unknown;
    }

    final double avgHipY = (leftHip.y + rightHip.y) / 2;
    final double avgKneeY = (leftKnee.y + rightKnee.y) / 2;

    // If knees are significantly below hips → standing. If close → sitting.
    final double hipKneeDiff = avgKneeY - avgHipY;

    // Check if ankles are visible and below knees → standing
    if (leftAnkle != null && rightAnkle != null) {
      final double avgAnkleY = (leftAnkle.y + rightAnkle.y) / 2;
      if (avgAnkleY > avgKneeY && hipKneeDiff > 80) {
        return _Posture.standing;
      }
    }

    if (hipKneeDiff < 50) {
      return _Posture.sitting;
    }

    return _Posture.standing;
  }

  String? _analyzeArms(Pose pose) {
    final PoseLandmark? leftShoulder =
        pose.landmarks[PoseLandmarkType.leftShoulder];
    final PoseLandmark? rightShoulder =
        pose.landmarks[PoseLandmarkType.rightShoulder];
    final PoseLandmark? leftWrist =
        pose.landmarks[PoseLandmarkType.leftWrist];
    final PoseLandmark? rightWrist =
        pose.landmarks[PoseLandmarkType.rightWrist];

    if (leftShoulder == null || rightShoulder == null) return null;

    bool leftRaised = false;
    bool rightRaised = false;

    // Wrist above shoulder → arm raised
    if (leftWrist != null && leftWrist.y < leftShoulder.y - 30) {
      leftRaised = true;
    }
    if (rightWrist != null && rightWrist.y < rightShoulder.y - 30) {
      rightRaised = true;
    }

    if (leftRaised && rightRaised) {
      return 'both arms raised';
    } else if (leftRaised) {
      return 'raising their left hand';
    } else if (rightRaised) {
      return 'raising their right hand';
    }
    return null;
  }

  String? _horizontalPosition(Pose pose) {
    final PoseLandmark? nose = pose.landmarks[PoseLandmarkType.nose];
    if (nose == null) return null;

    // Rough position from nose X coordinate.
    // Image width is unknown, but we can use the nose X relative to a
    // rough estimate. ML Kit returns pixel coordinates.
    // Without image dimensions we skip this.
    return null;
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _detector.close();
  }
}

enum _Posture {
  standing('appears to be standing'),
  sitting('appears to be sitting'),
  unknown('posture unclear');

  const _Posture(this.label);
  final String label;
}
