import 'package:lumisense/services/tts_service.dart';
import 'package:lumisense/services/yolo_service.dart';

/// Manages the smart TTS announcement pipeline for navigation mode.
///
/// Objects are announced only when they are:
/// 1. **Confirmed** — seen in at least [_persistenceThreshold] consecutive frames
/// 2. **New** — not already in the previously announced set
/// 3. **Off cooldown** — at least [announcementCooldown] since last TTS call
///
/// This prevents rapid-fire speech and false-positive announcements while
/// providing a natural, calm narration of the user's surroundings.
class NavigationModeController {
  NavigationModeController({
    required TtsService tts,
    this.announcementCooldown = const Duration(seconds: 3),
    this.persistenceThreshold = 2,
    this.forgetDuration = const Duration(seconds: 5),
  }) : _tts = tts;

  final TtsService _tts;

  /// Minimum time between TTS announcements.
  final Duration announcementCooldown;

  /// Number of consecutive frames an object must appear before being confirmed.
  final int persistenceThreshold;

  /// How long after an object disappears before it is "forgotten" and can be
  /// re-announced if it reappears.
  final Duration forgetDuration;

  // ─── State ──────────────────────────────────────────────────────────────────

  /// Objects currently detected in the latest frame.
  Set<String> _currentLabels = {};

  /// Objects that have passed the persistence threshold.
  final Set<String> _confirmedLabels = {};

  /// Objects that have already been announced and are still in view.
  final Set<String> _announcedLabels = {};

  /// Tracks consecutive frame count for each label.
  final Map<String, int> _frameCount = {};

  /// When each label was last seen — used for forget logic.
  final Map<String, DateTime> _lastSeen = {};

  DateTime _lastAnnouncementTime = DateTime(2000);
  bool _isSpeaking = false;

  /// Tracks whether we've previously made a confirmed-object announcement.
  /// Used to trigger the "path is clear" announcement when everything disappears.
  bool _previouslyHadConfirmedObjects = false;

  // ─── FPS tracking ───────────────────────────────────────────────────────────

  int _framesSinceLastFps = 0;
  DateTime _lastFpsTime = DateTime.now();
  double _currentFps = 0;

  /// Current inference FPS (updated every second).
  double get fps => _currentFps;

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Call this for every YOLO inference result. Updates internal state,
  /// triggers TTS when appropriate, and returns the set of confirmed labels.
  Set<String> updateDetections(List<YoloDetection> detections) {
    final DateTime now = DateTime.now();
    _updateFps(now);

    _currentLabels = detections.map((d) => d.label).toSet();

    // Update persistence counters.
    for (final String label in _currentLabels) {
      _frameCount[label] = (_frameCount[label] ?? 0) + 1;
      _lastSeen[label] = now;

      if ((_frameCount[label] ?? 0) >= persistenceThreshold) {
        _confirmedLabels.add(label);
      }
    }

    // Decrement/remove labels that disappeared from this frame.
    final Set<String> disappeared = _frameCount.keys
        .toSet()
        .difference(_currentLabels);
    for (final String label in disappeared) {
      _frameCount[label] = (_frameCount[label] ?? 1) - 1;
      if ((_frameCount[label] ?? 0) <= 0) {
        _frameCount.remove(label);
        _confirmedLabels.remove(label);
      }
    }

    // Forget objects that haven't been seen for a while.
    _forgetOldObjects(now);

    // Announce new confirmed objects.
    _maybeAnnounce(now);

    return Set<String>.from(_confirmedLabels);
  }

  /// Resets all tracking state. Call when toggling navigation mode off.
  void reset() {
    _currentLabels = {};
    _confirmedLabels.clear();
    _announcedLabels.clear();
    _frameCount.clear();
    _lastSeen.clear();
    _isSpeaking = false;
    _previouslyHadConfirmedObjects = false;
    _currentFps = 0;
    _framesSinceLastFps = 0;
  }

  void dispose() {
    // Nothing to dispose — timers are not used.
  }

  // ─── Private ────────────────────────────────────────────────────────────────

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
    }
  }

  void _maybeAnnounce(DateTime now) {
    if (_isSpeaking) return;
    if (now.difference(_lastAnnouncementTime) < announcementCooldown) return;

    // Find confirmed objects that haven't been announced yet.
    final Set<String> newObjects =
        _confirmedLabels.difference(_announcedLabels);

    if (newObjects.isNotEmpty) {
      // Build announcement text.
      final List<String> sorted = newObjects.toList()..sort();
      final String text = sorted.length == 1
          ? sorted.first
          : '${sorted.sublist(0, sorted.length - 1).join(', ')} and ${sorted.last}';

      _isSpeaking = true;
      _lastAnnouncementTime = now;
      _announcedLabels.addAll(newObjects);
      _previouslyHadConfirmedObjects = true;

      _tts.speak(text).whenComplete(() {
        _isSpeaking = false;
      });
      return;
    }

    // Announce "path is clear" when all previously announced objects disappear.
    if (_previouslyHadConfirmedObjects &&
        _confirmedLabels.isEmpty &&
        _announcedLabels.isEmpty) {
      _previouslyHadConfirmedObjects = false;
      _isSpeaking = true;
      _lastAnnouncementTime = now;

      _tts.speak('Path is clear.').whenComplete(() {
        _isSpeaking = false;
      });
    }
  }
}
