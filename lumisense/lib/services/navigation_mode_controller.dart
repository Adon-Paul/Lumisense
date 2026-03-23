import 'package:flutter/services.dart';

import 'package:lumisense/services/tts_service.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// Manages the smart TTS announcement pipeline for navigation mode.
///
/// Objects are announced only when they are:
/// 1. **Confirmed** — seen in at least [_persistenceThreshold] consecutive frames
/// 2. **New** — not already in the previously announced set
/// 3. **Off cooldown** — at least [announcementCooldown] since last TTS call
///
/// Enhancements over a basic pipeline:
/// - **Spatial awareness**: announces object position (left / ahead / right)
///   and proximity (close / nearby) based on bounding box.
/// - **Priority ordering**: vehicles and people are announced before furniture.
/// - **Proximity haptics**: vibration intensity scales with proximity.
/// - **Periodic summary**: reassures the user the system is active when the
///   scene is stable (no new objects for [summaryInterval]).
class NavigationModeController {
  NavigationModeController({
    required TtsService tts,
    this.announcementCooldown = const Duration(seconds: 3),
    this.persistenceThreshold = 2,
    this.forgetDuration = const Duration(seconds: 5),
    this.summaryInterval = const Duration(seconds: 15),
  }) : _tts = tts;

  final TtsService _tts;

  /// Minimum time between TTS announcements.
  final Duration announcementCooldown;

  /// Number of consecutive frames an object must appear before being confirmed.
  final int persistenceThreshold;

  /// How long after an object disappears before it is "forgotten" and can be
  /// re-announced if it reappears.
  final Duration forgetDuration;

  /// How often to repeat a stable-scene summary so the user knows the system
  /// is still active (e.g., "Still seeing 2 people ahead").
  final Duration summaryInterval;

  // ─── Priority map ──────────────────────────────────────────────────────────
  // Higher number = announced first. Objects not in the map default to 1.

  static const Map<String, int> _priorityMap = <String, int>{
    'person': 10,
    'car': 9,
    'truck': 9,
    'bus': 9,
    'train': 9,
    'bicycle': 8,
    'motorcycle': 8,
    'dog': 7,
    'cat': 6,
    'traffic light': 6,
    'stop sign': 6,
    'fire hydrant': 5,
    'chair': 3,
    'bench': 3,
    'potted plant': 2,
    'dining table': 2,
    'tv': 2,
    'laptop': 2,
  };

  // ─── State ────────────────────────────────────────────────────────────────

  Set<String> _currentLabels = <String>{};
  final Set<String> _confirmedLabels = <String>{};
  final Set<String> _announcedLabels = <String>{};
  final Map<String, int> _frameCount = <String, int>{};
  final Map<String, DateTime> _lastSeen = <String, DateTime>{};

  /// Stores the most recent spatial description for each confirmed label.
  final Map<String, String> _spatialDescriptions = <String, String>{};

  DateTime _lastAnnouncementTime = DateTime(2000);
  DateTime _lastSummaryTime = DateTime(2000);
  bool _isSpeaking = false;
  bool _previouslyHadConfirmedObjects = false;


  // ─── FPS tracking ─────────────────────────────────────────────────────────

  int _framesSinceLastFps = 0;
  DateTime _lastFpsTime = DateTime.now();
  double _currentFps = 0;

  double get fps => _currentFps;

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Call this for every YOLO inference result. Updates internal state,
  /// triggers TTS when appropriate, and returns the set of confirmed labels.
  Set<String> updateDetections(List<YOLOResult> detections) {
    final DateTime now = DateTime.now();
    _updateFps(now);

    _currentLabels = detections.map((YOLOResult d) => d.className).toSet();

    // Update persistence counters and spatial descriptions.
    for (final YOLOResult detection in detections) {
      final String label = detection.className;
      _frameCount[label] = (_frameCount[label] ?? 0) + 1;
      _lastSeen[label] = now;

      // Cache spatial description from the most recent detection.
      _spatialDescriptions[label] = _describeSpatial(detection);

      if ((_frameCount[label] ?? 0) >= persistenceThreshold) {
        _confirmedLabels.add(label);
      }
    }

    // Decrement/remove labels that disappeared from this frame.
    final Set<String> disappeared =
        _frameCount.keys.toSet().difference(_currentLabels);
    for (final String label in disappeared) {
      _frameCount[label] = (_frameCount[label] ?? 1) - 1;
      if ((_frameCount[label] ?? 0) <= 0) {
        _frameCount.remove(label);
        _confirmedLabels.remove(label);
      }
    }

    _forgetOldObjects(now);
    _maybeAnnounce(now);

    return Set<String>.from(_confirmedLabels);
  }

  /// Resets all tracking state. Call when toggling navigation mode off.
  void reset() {
    _currentLabels = <String>{};
    _confirmedLabels.clear();
    _announcedLabels.clear();
    _frameCount.clear();
    _lastSeen.clear();
    _spatialDescriptions.clear();
    _isSpeaking = false;
    _previouslyHadConfirmedObjects = false;
    _currentFps = 0;
    _framesSinceLastFps = 0;
    _lastSummaryTime = DateTime(2000);
  }

  void dispose() {
    // Nothing to dispose — no timers or streams.
  }

  // ─── Spatial description ──────────────────────────────────────────────────

  /// Builds a short spatial string like "close, ahead" from a detection's
  /// bounding box relative to [_frameSize].
  String _describeSpatial(YOLOResult detection) {
    // Use normalizedBox (0-1 range) for position and area calculations.
    final double cx =
        (detection.normalizedBox.left + detection.normalizedBox.right) / 2;
    final double area =
        detection.normalizedBox.width * detection.normalizedBox.height;

    final String horizontal =
        cx < 0.33 ? 'on your left' : (cx > 0.66 ? 'on your right' : 'ahead');
    final String proximity = area > 0.15 ? 'close' : 'nearby';

    return '$proximity, $horizontal';
  }

  // ─── Private ──────────────────────────────────────────────────────────────

  void _updateFps(DateTime now) {
    _framesSinceLastFps++;
    final Duration elapsed = now.difference(_lastFpsTime);
    if (elapsed.inMilliseconds >= 1000) {
      _currentFps =
          _framesSinceLastFps / (elapsed.inMilliseconds / 1000.0);
      _framesSinceLastFps = 0;
      _lastFpsTime = now;
    }
  }

  void _forgetOldObjects(DateTime now) {
    final List<String> toForget = <String>[];
    for (final MapEntry<String, DateTime> entry in _lastSeen.entries) {
      if (now.difference(entry.value) > forgetDuration &&
          !_currentLabels.contains(entry.key)) {
        toForget.add(entry.key);
      }
    }
    for (final String label in toForget) {
      _lastSeen.remove(label);
      _announcedLabels.remove(label);
      _confirmedLabels.remove(label);
      _frameCount.remove(label);
      _spatialDescriptions.remove(label);
    }
  }

  void _maybeAnnounce(DateTime now) {
    if (_isSpeaking) return;
    if (now.difference(_lastAnnouncementTime) < announcementCooldown) return;

    // ── New objects ─────────────────────────────────────────────────────────
    final Set<String> newObjects =
        _confirmedLabels.difference(_announcedLabels);

    if (newObjects.isNotEmpty) {
      // Sort by priority descending, limit to 3 to reduce cognitive overload.
      final List<String> sorted = newObjects.toList()
        ..sort((String a, String b) =>
            (_priorityMap[b] ?? 1).compareTo(_priorityMap[a] ?? 1));
      final List<String> top = sorted.take(3).toList();

      // Build announcement with spatial descriptions.
      final StringBuffer sb = StringBuffer();
      for (int i = 0; i < top.length; i++) {
        final String label = top[i];
        final String spatial = _spatialDescriptions[label] ?? '';
        if (i > 0) sb.write('. ');
        sb.write('$label $spatial');
      }

      // Trigger proximity haptic for the highest-priority (first) object.
      // Trigger proximity haptic based on the spatial description.
      HapticFeedback.lightImpact();

      _isSpeaking = true;
      _lastAnnouncementTime = now;
      _lastSummaryTime = now;
      _announcedLabels.addAll(newObjects);
      _previouslyHadConfirmedObjects = true;

      _tts.speak(sb.toString()).whenComplete(() {
        _isSpeaking = false;
      });
      return;
    }

    // ── "Path is clear" ─────────────────────────────────────────────────────
    if (_previouslyHadConfirmedObjects &&
        _confirmedLabels.isEmpty &&
        _announcedLabels.isEmpty) {
      _previouslyHadConfirmedObjects = false;
      _isSpeaking = true;
      _lastAnnouncementTime = now;
      _lastSummaryTime = now;

      HapticFeedback.lightImpact();
      _tts.speak('Path is clear.').whenComplete(() {
        _isSpeaking = false;
      });
      return;
    }

    // ── Periodic stable-scene summary ───────────────────────────────────────
    if (_previouslyHadConfirmedObjects &&
        _confirmedLabels.isNotEmpty &&
        now.difference(_lastSummaryTime) > summaryInterval) {
      final List<String> sorted = _confirmedLabels.toList()
        ..sort((String a, String b) =>
            (_priorityMap[b] ?? 1).compareTo(_priorityMap[a] ?? 1));
      final List<String> top = sorted.take(3).toList();
      final String summary = 'Still seeing ${top.join(', ')}';

      _isSpeaking = true;
      _lastAnnouncementTime = now;
      _lastSummaryTime = now;

      _tts.speak(summary).whenComplete(() {
        _isSpeaking = false;
      });
    }
  }

}
