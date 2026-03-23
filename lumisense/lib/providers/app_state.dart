import 'package:flutter/foundation.dart';

/// Represents the current processing lifecycle of the assistant.
enum ProcessingState {
  idle,
  listening,
  processing,
  speaking,
}

/// Represents the active mode / screen-intent of the app.
enum AppMode {
  home,
  camera,
  readText,
  identifyObjects,
  describeScene,
  navigation,
  sos,
  settings,
  history,
}

/// Global UI/session state for LumiSense.
///
/// Register with [MultiProvider] so any screen or service can react to
/// processing-state and mode changes without direct coupling.
class AppStateProvider extends ChangeNotifier {
  ProcessingState _processingState = ProcessingState.idle;
  AppMode _currentMode = AppMode.home;

  ProcessingState get processingState => _processingState;
  AppMode get currentMode => _currentMode;

  // ─── Setters ─────────────────────────────────────────────────────────────────

  set processingState(ProcessingState value) {
    if (_processingState == value) return;
    _processingState = value;
    notifyListeners();
  }

  set currentMode(AppMode value) {
    if (_currentMode == value) return;
    _currentMode = value;
    notifyListeners();
  }

  // ─── Granular reset helpers ───────────────────────────────────────────────────
  //
  // Keeping the two axes independent prevents a screen from accidentally
  // resetting navigation mode when it only wants to signal "done processing".

  /// Resets [processingState] to [ProcessingState.idle] only.
  ///
  /// Use this when an AI pipeline finishes and you want to mark the session
  /// idle without affecting which screen / mode the user is on.
  void resetProcessingState() {
    if (_processingState == ProcessingState.idle) return;
    _processingState = ProcessingState.idle;
    notifyListeners();
  }

  /// Resets [currentMode] to [AppMode.home] only.
  ///
  /// Use this when the user explicitly navigates back to the home screen.
  void resetMode() {
    if (_currentMode == AppMode.home) return;
    _currentMode = AppMode.home;
    notifyListeners();
  }

  /// Resets both [processingState] and [currentMode] in a single
  /// [notifyListeners] call — use only when both truly need to go back to
  /// their defaults at the same time (e.g., on hard app reset).
  void resetAll() {
    bool hasChanges = false;

    if (_processingState != ProcessingState.idle) {
      _processingState = ProcessingState.idle;
      hasChanges = true;
    }

    if (_currentMode != AppMode.home) {
      _currentMode = AppMode.home;
      hasChanges = true;
    }

    if (hasChanges) notifyListeners();
  }
}
