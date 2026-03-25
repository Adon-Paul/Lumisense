import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:lumisense/models/history_entry.dart';
import 'package:lumisense/models/ocr_result.dart';
import 'package:lumisense/providers/app_state.dart';
import 'package:lumisense/providers/history_provider.dart';
import 'package:lumisense/providers/settings_provider.dart';
import 'package:lumisense/services/directions_service.dart';
import 'package:lumisense/services/gemini_service.dart';
import 'package:lumisense/services/model_manager.dart';
import 'package:lumisense/services/on_device_orchestrator.dart';
import 'package:lumisense/services/on_device_vision_service.dart';
import 'package:lumisense/services/navigation_mode_controller.dart';
import 'package:lumisense/models/upi_payment_info.dart';
import 'package:lumisense/services/brightness_detector_service.dart';
import 'package:lumisense/services/contact_caller_service.dart';
import 'package:lumisense/services/currency_detector_service.dart';
import 'package:lumisense/services/face_detection_service.dart';
import 'package:lumisense/services/pose_detection_service.dart';
import 'package:lumisense/services/ocr_service.dart';
import 'package:lumisense/services/qr_scanner_service.dart';
import 'package:lumisense/services/upi_payment_service.dart';
import 'package:lumisense/services/weather_service.dart';
import 'package:lumisense/services/sos_service.dart';
import 'package:lumisense/services/stt_service.dart';
import 'package:lumisense/services/tts_service.dart';
import 'package:lumisense/utils/theme.dart';
import 'package:lumisense/widgets/bounding_box_overlay.dart';
import 'package:lumisense/widgets/directions_panel.dart';
import 'package:lumisense/screens/route_map_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';

/// Specifies an action to auto-trigger when the camera screen opens.
///
/// Used by the home screen quick-access buttons so blind users don't
/// have to navigate to the camera and tap a second time.
enum CameraInitialAction {
  none,
  read,
  identify,
  describe,
  navigate,
  scanPayment,
  identifyCurrency,
  checkBrightness,
  checkWeather,
  detectPeople,
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    this.initialAction = CameraInitialAction.none,
  });

  /// If set, the camera screen will automatically trigger this action
  /// once the camera is initialized and the first frame is ready.
  final CameraInitialAction initialAction;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  // ─── Constants ─────────────────────────────────────────────────────────────

  /// Minimum interval between Gemini API calls to prevent quota burn.
  static const Duration _geminiCooldown = Duration(seconds: 5);

  /// Maximum characters per TTS chunk for Power Read mode.
  static const int _chunkSize = 220;

  /// Duration of the SOS countdown before sending.
  static const int _sosCountdownSeconds = 5;

  /// Timeout for YOLO model to become ready after camera permission granted.
  static const Duration _yoloTimeout = Duration(seconds: 20);

  // ─── Services ─────────────────────────────────────────────────────────────

  final OcrService _ocrService = OcrService();
  final QrScannerService _qrScannerService = QrScannerService();
  final UpiPaymentService _upiPaymentService = const UpiPaymentService();
  final BrightnessDetectorService _brightnessService =
      const BrightnessDetectorService();
  final ContactCallerService _contactCallerService =
      const ContactCallerService();
  final WeatherService _weatherService = const WeatherService();
  CurrencyDetectorService? _currencyDetectorService;
  String? _currencyApiKey;
  FaceDetectionService? _faceDetectionService;
  PoseDetectionService? _poseDetectionService;
  final SttService _sttService = SttService();
  late final NavigationModeController _navController;
  GeminiService? _geminiService;
  String? _geminiApiKey;
  String? _openRouterApiKey;
  OnDeviceOrchestrator? _onDeviceOrchestrator;

  // ─── Turn-by-turn navigation ────────────────────────────────────────────
  DirectionsService? _directionsService;
  String? _directionsOrsKey;

  // ─── Permission state ─────────────────────────────────────────────────────

  bool _hasPermission = false;
  bool _permissionPermanentlyDenied = false;
  String? _cameraError;

  // ─── UI state ─────────────────────────────────────────────────────────────

  String? _statusMessage;
  String? _lastResultPreview;
  bool _isProcessing = false;
  bool _isListening = false;
  bool _initialActionTriggered = false;
  bool _pendingInitialNavigateRetry = false;

  // ─── SOS countdown state ──────────────────────────────────────────────────

  bool _sosPending = false;

  // ─── Directions panel state ─────────────────────────────────────────────

  bool _showDirectionsPanel = false;

  // ─── YOLO / navigation state ──────────────────────────────────────────────

  final YOLOViewController _yoloController = YOLOViewController();
  bool _yoloViewReady = false;
  bool _yoloTimedOut = false;
  bool _isNavigating = false;
  List<YOLOResult> _lastDetections = const <YOLOResult>[];
  double _navFps = 0;
  Timer? _yoloTimeoutTimer;

  // ═══════════════════════════════════════════════════════════════════════════
  // Lifecycle
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _navController =
        NavigationModeController(tts: context.read<TtsService>());
    _ensureCameraPermission();
    _initStt();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_isNavigating) _stopNavigation(announce: false);
      // Note: we do NOT stop turn-by-turn navigation on lifecycle change
      // — GPS tracking should continue in background for walking directions.
      context.read<TtsService>().stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _yoloTimeoutTimer?.cancel();
    unawaited(_ocrService.dispose());
    unawaited(_qrScannerService.dispose());
    if (_faceDetectionService != null) unawaited(_faceDetectionService!.dispose());
    if (_poseDetectionService != null) unawaited(_poseDetectionService!.dispose());
    unawaited(_sttService.dispose());
    _navController.dispose();
    _directionsService?.removeListener(_onDirectionsChanged);
    _directionsService?.dispose();
    _onDeviceOrchestrator?.cancelAll();
    unawaited(_onDeviceOrchestrator?.dispose() ?? Future.value());
    super.dispose();
  }

  // ─── Permission ───────────────────────────────────────────────────────────

  Future<void> _ensureCameraPermission() async {
    PermissionStatus status = await Permission.camera.status;
    if (status.isGranted) {
      if (mounted) {
        setState(() => _hasPermission = true);
        _startYoloTimeout();
      }
      return;
    }

    status = await Permission.camera.request();
    if (!mounted) return;

    if (status.isGranted) {
      setState(() => _hasPermission = true);
      _startYoloTimeout();
      return;
    }

    final bool permanently =
        status.isPermanentlyDenied || status.isRestricted;
    setState(() {
      _permissionPermanentlyDenied = permanently;
      _cameraError = permanently
          ? 'Camera permission is blocked. Open settings to enable camera access.'
          : 'Camera permission denied. Allow camera access to continue.';
    });
  }

  /// Starts a timeout timer that warns the user if YOLO doesn't load.
  void _startYoloTimeout() {
    _yoloTimeoutTimer = Timer(_yoloTimeout, () {
      if (!mounted || _yoloViewReady) return;
      setState(() => _yoloTimedOut = true);
      context.read<TtsService>().speak(
        'Object detection is taking longer than expected. '
        'Read Text and Describe Scene are still available.',
      );
    });
  }

  Future<void> _openAppSettings() async {
    await openAppSettings();
  }

  // ─── STT ──────────────────────────────────────────────────────────────────

  Future<void> _initStt() async {
    try {
      final bool available = await _sttService.init();
      if (!available) {
        debugPrint('CameraScreen: STT not available on this device.');
      }
    } catch (e) {
      debugPrint('CameraScreen: STT init failed: $e');
    }
    _sttService.onCommand = _handleVoiceCommand;
    _sttService.onListeningChanged = (bool listening) {
      if (mounted) setState(() => _isListening = listening);
    };

    // Wire TTS completion → STT auto-resume.
    final tts = context.read<TtsService>();
    tts.onSpeakComplete = () {
      if (mounted) _sttService.resumeAfterTts();
    };
    tts.onSpeakCancel = () {
      if (mounted) _sttService.resumeAfterTts();
    };
  }

  void _handleVoiceCommand(VoiceCommand command, String rawText) {
    // Mute mic while we process + speak. TTS onSpeakComplete resumes it.
    _sttService.pauseForTts();

    // Stop and SOS are high-priority interrupts — always allowed.
    switch (command) {
      case VoiceCommand.stop:
        final TtsService tts = context.read<TtsService>();
        tts.chunkReadingCancelled = true;
        tts.stop();
        if (_sosPending) {
          _sosPending = false;
          tts.speak('SOS cancelled.');
          return;
        }
        if (_directionsService?.isActive ?? false) {
          _stopTurnByTurnNavigation();
          tts.speak('Walking directions stopped.');
          return;
        }
        // Nothing to stop — just resume listening
        _sttService.resumeAfterTts();
        return;
      case VoiceCommand.sos:
        _onSosTap();
        return;
      default:
        break;
    }

    // Navigation-specific commands work even while navigating.
    switch (command) {
      case VoiceCommand.navigateTo:
        final String dest = SttService.extractDestination(rawText);
        if (dest.isNotEmpty) {
          _startTurnByTurnNavigation(dest);
        } else {
          context.read<TtsService>().speak(
            'Please say "navigate to" followed by a place name.',
          );
        }
        return;
      case VoiceCommand.repeatDirection:
        _directionsService?.repeatCurrentStep();
        // repeatCurrentStep speaks via TTS → onSpeakComplete resumes
        return;
      case VoiceCommand.whereAmI:
        _directionsService?.announceStatus();
        return;
      default:
        break;
    }

    if (_isProcessing) {
      _sttService.resumeAfterTts();
      return;
    }

    switch (command) {
      case VoiceCommand.readText:
        _onReadTap();
      case VoiceCommand.identifyObjects:
        _onIdentifyTap();
      case VoiceCommand.describeScene:
        _onDescribeTap();
      case VoiceCommand.scanPayment:
        _onPayTap();
      case VoiceCommand.identifyCurrency:
        _onCurrencyTap();
      case VoiceCommand.checkBrightness:
        _onBrightnessTap();
      case VoiceCommand.checkWeather:
        _onWeatherTap();
      case VoiceCommand.callContact:
        _onCallContactTap(rawText);
      case VoiceCommand.detectPeople:
        _onPeopleTap();
      case VoiceCommand.navigation:
        _toggleNavigation();
      case VoiceCommand.toggleOnDevice:
        _toggleOnDeviceMode();
      case VoiceCommand.help:
        context.read<TtsService>().speak(SttService.helpText);
      case VoiceCommand.unknown:
        context
            .read<TtsService>()
            .speak('I did not understand that command. Say help for options.');
      case VoiceCommand.stop:
      case VoiceCommand.sos:
      case VoiceCommand.navigateTo:
      case VoiceCommand.repeatDirection:
      case VoiceCommand.whereAmI:
        break;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // YOLO callbacks
  // ═══════════════════════════════════════════════════════════════════════════

  void _onYoloResult(List<YOLOResult> results) {
    if (!_yoloViewReady) {
      _yoloViewReady = true;
      _yoloTimeoutTimer?.cancel();
      _triggerInitialActionIfNeeded();
      _retryPendingInitialNavigate();
    }

    _lastDetections = results;

    if (_isNavigating && mounted) {
      _navController.updateDetections(results);
      setState(() {
        _navFps = _navController.fps;
        _lastResultPreview = results.isEmpty
            ? 'Scanning surroundings...'
            : '${results.length} objects: ${results.take(3).map((YOLOResult d) => '${d.className} ${(d.confidence * 100).toStringAsFixed(0)}%').join(', ')}';
      });
    }
  }

  void _onPerformanceMetrics(YOLOPerformanceMetrics metrics) {
    if (_isNavigating && mounted) {
      setState(() => _navFps = metrics.fps);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Navigation Mode
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _toggleOnDeviceMode() async {
    final TtsService tts = context.read<TtsService>();
    final SettingsProvider settings = context.read<SettingsProvider>();
    final bool newValue = !settings.useOnDeviceModels;
    await settings.setUseOnDeviceModels(newValue);
    HapticFeedback.mediumImpact();
    tts.speak(
      newValue
          ? 'Switched to on-device A I. Models will run locally.'
          : 'Switched to cloud A I. Using online providers.',
    );
  }

  void _toggleNavigation() {
    if (!_yoloViewReady) {
      context.read<TtsService>().speak(
        'Navigation mode is not available yet. Please wait for the model to load.',
      );
      return;
    }
    _isNavigating ? _stopNavigation(announce: true) : _startNavigation();
  }

  void _startNavigation() {
    if (_isNavigating) return;

    final TtsService tts = context.read<TtsService>();
    final AppStateProvider appState = context.read<AppStateProvider>();

    setState(() {
      _isNavigating = true;
      _statusMessage = 'Navigation mode active';
      _lastResultPreview = 'Scanning surroundings...';
    });

    appState.currentMode = AppMode.navigation;
    HapticFeedback.mediumImpact();
    // ignore: deprecated_member_use
    SemanticsService.announce('Navigation mode on', TextDirection.ltr);
    unawaited(tts.speak('Navigation mode on.'));
  }

  void _stopNavigation({bool announce = true}) {
    if (!_isNavigating) return;
    _navController.reset();

    if (mounted) {
      setState(() {
        _isNavigating = false;
        _navFps = 0;
        _statusMessage = null;
        _lastResultPreview = null;
      });
    }

    if (announce) {
      HapticFeedback.mediumImpact();
      // ignore: deprecated_member_use
    SemanticsService.announce('Navigation mode off', TextDirection.ltr);
      unawaited(context.read<TtsService>().speak('Navigation mode off.'));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Turn-by-Turn Walking Navigation (OpenRouteService)
  // ═══════════════════════════════════════════════════════════════════════════

  DirectionsService _getDirectionsService(String orsApiKey) {
    if (_directionsService == null || _directionsOrsKey != orsApiKey) {
      // Remove listener from old service before disposing.
      _directionsService?.removeListener(_onDirectionsChanged);
      _directionsService?.dispose();
      _directionsService = DirectionsService(
        apiKey: orsApiKey,
        tts: context.read<TtsService>(),
      );
      _directionsOrsKey = orsApiKey;
      // Listen for state changes to update UI.
      _directionsService!.addListener(_onDirectionsChanged);
    }
    return _directionsService!;
  }

  void _onDirectionsChanged() {
    if (!mounted) return;
    final DirectionsService? ds = _directionsService;
    if (ds == null) return;

    setState(() {
      if (ds.isNavigating || ds.state == NavSessionState.fetchingRoute ||
          ds.state == NavSessionState.rerouting) {
        final NavigationStep? step = ds.currentStep;
        _statusMessage = ds.state == NavSessionState.fetchingRoute
            ? 'Finding route...'
            : ds.state == NavSessionState.rerouting
                ? 'Recalculating route...'
                : 'Walking to ${ds.destinationLabel ?? "destination"}';
        _lastResultPreview = step?.spokenInstruction ??
            'Route to ${ds.destinationLabel ?? "destination"}';
      } else if (ds.state == NavSessionState.arrived) {
        _statusMessage = 'Arrived!';
        _lastResultPreview =
            'You have arrived at ${ds.destinationLabel ?? "your destination"}.';
      }
    });

    // Auto-start obstacle detection alongside directions.
    if (ds.isNavigating && !_isNavigating && _yoloViewReady) {
      _startNavigation();
    }

    // Auto-show directions panel when route is active.
    if (ds.isActive && !_showDirectionsPanel) {
      _showDirectionsPanel = true;
    }
  }

  Future<void> _startTurnByTurnNavigation(String destination) async {
    final SettingsProvider settings = context.read<SettingsProvider>();
    final TtsService tts = context.read<TtsService>();

    if (!settings.hasOrsApiKey) {
      await tts.speak(
        'No navigation API key configured. '
        'Please add your free OpenRouteService key in Settings.',
      );
      return;
    }

    HapticFeedback.mediumImpact();
    final DirectionsService ds = _getDirectionsService(settings.orsApiKey);

    // If already navigating, stop first.
    if (ds.isActive) {
      ds.stopNavigation();
    }

    setState(() {
      _statusMessage = 'Finding route to $destination...';
      _lastResultPreview = null;
    });

    final bool success = await ds.startNavigation(
      destinationQuery: destination,
    );

    if (success && mounted) {
      // ignore: deprecated_member_use
      SemanticsService.announce(
        'Walking directions started to ${ds.destinationLabel}',
        TextDirection.ltr,
      );
    }
  }

  void _stopTurnByTurnNavigation() {
    _directionsService?.stopNavigation();
    if (mounted) {
      setState(() {
        _statusMessage = null;
        _lastResultPreview = null;
      });
    }
  }

  void _openRouteMap() {
    final DirectionsService? ds = _directionsService;
    if (ds == null || ds.route == null) {
      context.read<TtsService>().speak('No route available to display on the map.');
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RouteMapScreen(
          directionsService: ds,
          tts: context.read<TtsService>(),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Frame Capture Helper
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Uint8List> _captureFrame() async {
    try {
      final Uint8List? result = await _yoloController.captureFrame();
      if (result != null && result.length > 100) return result;
    } catch (e) {
      debugPrint('captureFrame failed: $e');
    }
    throw StateError('Unable to capture camera frame. Please try again.');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OCR (Read Text)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _onReadTap() async {
    if (_isProcessing) return;
    HapticFeedback.selectionClick();

    final TtsService tts = context.read<TtsService>();
    final AppStateProvider appState = context.read<AppStateProvider>();
    final HistoryProvider history = context.read<HistoryProvider>();

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Reading text...';
      _lastResultPreview = null;
    });

    appState.currentMode = AppMode.readText;
    appState.processingState = ProcessingState.processing;
    // ignore: deprecated_member_use
    SemanticsService.announce('Reading text', TextDirection.ltr);

    File? tempFile;
    try {
      final Uint8List frameBytes = await _captureFrame();
      if (!mounted) return;

      final Directory tempDir = await getTemporaryDirectory();
      tempFile = File('${tempDir.path}/lumisense_capture.jpg');
      await tempFile.writeAsBytes(frameBytes);

      final OcrResult result =
          await _ocrService.extractTextFromImagePath(tempFile.path);
      if (!mounted) return;

      final String spokenText = result.hasText
          ? result.text
          : 'No readable text detected. Please move closer and try again.';

      setState(() {
        _statusMessage = result.hasText
            ? 'Text captured in ${result.processingTimeMs} ms'
            : 'No text detected';
        _lastResultPreview = result.hasText
            ? result.text
            : 'No readable text detected. Point at text and try again.';
      });

      if (result.hasText) {
        await history.addEntry(
          type: HistoryEntryType.ocr,
          title: 'Read Text',
          content: result.text,
        );
      }

      appState.processingState = ProcessingState.speaking;
      if (_powerReadMode && result.hasText) {
        await _speakTextInChunks(tts, result.text);
      } else {
        await tts.speak(spokenText);
      }
    } catch (error) {
      if (!mounted) return;
      debugPrint('OCR error: $error');
      setState(() => _statusMessage = 'OCR failed. Please try again.');
      appState.processingState = ProcessingState.speaking;
      await tts.speak('Unable to read text right now. Please try again.');
    } finally {
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      appState.processingState = ProcessingState.idle;
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Object Identification (single-shot)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _onIdentifyTap() async {
    if (_isProcessing) return;

    if (!_yoloViewReady) {
      context.read<TtsService>().speak(
        'Object detection is still loading. Please wait a moment.',
      );
      return;
    }

    HapticFeedback.selectionClick();

    final TtsService tts = context.read<TtsService>();
    final AppStateProvider appState = context.read<AppStateProvider>();
    final HistoryProvider history = context.read<HistoryProvider>();

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Identifying objects...';
      _lastResultPreview = null;
    });

    appState.currentMode = AppMode.identifyObjects;
    appState.processingState = ProcessingState.processing;
    // ignore: deprecated_member_use
    SemanticsService.announce('Identifying objects', TextDirection.ltr);

    try {
      final List<YOLOResult> filtered = _lastDetections
          .where((YOLOResult d) => d.confidence >= 0.50)
          .take(5)
          .toList(growable: false);

      final String spokenText;
      final String previewText;

      if (filtered.isEmpty) {
        spokenText =
            'No clear objects detected. Please point to a nearby object and try again.';
        previewText =
            'No clear objects detected. Try better lighting or move closer.';
      } else {
        final List<String> labels =
            filtered.map((YOLOResult e) => e.className).toSet().toList();
        spokenText = 'I found ${labels.join(', ')}.';
        previewText = filtered
            .map((YOLOResult e) =>
                '${e.className} (${(e.confidence * 100).toStringAsFixed(0)}%)')
            .join(', ');
      }

      if (!mounted) return;

      setState(() {
        _statusMessage = filtered.isEmpty
            ? 'No objects detected'
            : 'Found ${filtered.length} objects';
        _lastResultPreview = previewText;
      });

      if (filtered.isNotEmpty) {
        await history.addEntry(
          type: HistoryEntryType.objectDetection,
          title: 'Object Identification',
          content: previewText,
        );
      }

      appState.processingState = ProcessingState.speaking;
      await tts.speak(spokenText);
    } catch (error) {
      if (!mounted) return;
      debugPrint('Identify error: $error');
      setState(() =>
          _statusMessage = 'Object identification failed. Please try again.');
      appState.processingState = ProcessingState.speaking;
      await tts
          .speak('Unable to identify objects right now. Please try again.');
    } finally {
      appState.processingState = ProcessingState.idle;
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Scene Description (Gemini) — with rate limiting
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _onDescribeTap() async {
    if (_isProcessing) return;
    HapticFeedback.lightImpact();

    final TtsService tts = context.read<TtsService>();
    final AppStateProvider appState = context.read<AppStateProvider>();
    final HistoryProvider history = context.read<HistoryProvider>();
    final SettingsProvider settings = context.read<SettingsProvider>();

    // Check if we can use on-device or cloud
    final bool useOnDevice = await _shouldUseOnDevice();

    if (!useOnDevice && settings.onDeviceOnly) {
      HapticFeedback.heavyImpact();
      await tts.speak(
        'On-device only mode is active but models are not downloaded. '
        'Please download them in Settings.',
      );
      return;
    }

    if (!useOnDevice && !settings.hasApiKey) {
      HapticFeedback.heavyImpact();
      await tts.speak(
        'No AI configured. Please download on-device models or add an API key in Settings.',
      );
      return;
    }

    // Rate limiting: prevent rapid successive calls.
    DateTime lastCall;
    if (useOnDevice) {
      final orchestrator = _getOrchestrator();
      lastCall = orchestrator.visionService.lastCallTime;
    } else {
      final GeminiService gemini = _getGeminiService(settings);
      lastCall = gemini.lastCallTime;
    }
    final Duration sinceLast = DateTime.now().difference(lastCall);
    if (sinceLast < _geminiCooldown) {
      await tts.speak('Please wait a moment before requesting another description.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = useOnDevice
          ? 'Describing scene (on-device)...'
          : 'Describing scene...';
      _lastResultPreview = null;
    });

    appState.currentMode = AppMode.describeScene;
    appState.processingState = ProcessingState.processing;
    // ignore: deprecated_member_use
    SemanticsService.announce('Describing scene', TextDirection.ltr);

    try {
      final Uint8List frameBytes = await _captureFrame();
      if (!mounted) return;

      String description;
      if (useOnDevice) {
        final orchestrator = _getOrchestrator();
        // Announce if model needs first-time loading into RAM
        if (!orchestrator.visionService.isReady) {
          setState(() => _statusMessage = 'Loading on-device AI model...');
          await tts.speak('Loading AI model. This may take a moment.');
        }
        description = await orchestrator.describeScene(frameBytes);
      } else {
        final GeminiService gemini = _getGeminiService(settings);
        description = await gemini.describeScene(frameBytes);
      }
      if (!mounted) return;

      setState(() {
        _statusMessage = useOnDevice
            ? 'Scene described (on-device)'
            : 'Scene described';
        _lastResultPreview = description;
      });

      await history.addEntry(
        type: HistoryEntryType.sceneDescription,
        title: useOnDevice
            ? 'Scene Description (On-Device)'
            : 'Scene Description',
        content: description,
      );

      appState.processingState = ProcessingState.speaking;
      await tts.speak(description);
    } on OnDeviceModelException catch (e) {
      if (!mounted) return;
      // If on-device-only mode, don't fall back to cloud
      if (settings.onDeviceOnly) {
        debugPrint('On-device failed (no cloud fallback): ${e.message}');
        setState(() => _statusMessage = 'On-device AI failed.');
        appState.processingState = ProcessingState.speaking;
        await tts.speak(
          'On-device AI failed: ${e.message}. '
          'Cloud fallback is disabled. Check your models in Settings.',
        );
      } else {
        // Fall back to cloud silently
        debugPrint('On-device failed, falling back to cloud: ${e.message}');
        try {
          final Uint8List frameBytes = await _captureFrame();
          if (!mounted) return;
          final GeminiService gemini = _getGeminiService(settings);
          final String description = await gemini.describeScene(frameBytes);
          if (!mounted) return;
          setState(() {
            _statusMessage = 'Scene described (cloud fallback)';
            _lastResultPreview = description;
          });
          await history.addEntry(
            type: HistoryEntryType.sceneDescription,
            title: 'Scene Description',
            content: description,
          );
          appState.processingState = ProcessingState.speaking;
          await tts.speak(description);
        } on GeminiApiException catch (cloudError) {
          if (!mounted) return;
          setState(() => _statusMessage = 'Description failed.');
          appState.processingState = ProcessingState.speaking;
          await tts.speak(cloudError.message);
        }
      }
    } on GeminiApiException catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Description failed.');
      appState.processingState = ProcessingState.speaking;
      await tts.speak(e.message);
    } catch (error) {
      if (!mounted) return;
      debugPrint('Describe error: $error');
      setState(
          () => _statusMessage = 'Description failed. Please try again.');
      appState.processingState = ProcessingState.speaking;
      await tts.speak(
          'Unable to describe the scene right now. Please try again.');
    } finally {
      appState.processingState = ProcessingState.idle;
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Currency Identification (Gemini Vision)
  // ═══════════════════════════════════════════════════════════════════════════

  CurrencyDetectorService _getCurrencyService(String apiKey) {
    if (_currencyDetectorService == null || _currencyApiKey != apiKey) {
      _currencyDetectorService = CurrencyDetectorService(apiKey: apiKey);
      _currencyApiKey = apiKey;
    }
    return _currencyDetectorService!;
  }

  Future<void> _onCurrencyTap() async {
    if (_isProcessing) return;
    HapticFeedback.mediumImpact();

    final TtsService tts = context.read<TtsService>();
    final SettingsProvider settings = context.read<SettingsProvider>();
    final AppStateProvider appState = context.read<AppStateProvider>();

    final bool useOnDevice = await _shouldUseOnDevice();

    if (!useOnDevice && settings.onDeviceOnly) {
      HapticFeedback.heavyImpact();
      await tts.speak(
        'On-device only mode is active but models are not downloaded. '
        'Please download them in Settings.',
      );
      return;
    }

    if (!useOnDevice && !settings.hasApiKey) {
      HapticFeedback.heavyImpact();
      await tts.speak(
        'No AI configured. Please download on-device models or add a Gemini key in Settings.',
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = useOnDevice
          ? 'Identifying currency (on-device)...'
          : 'Identifying currency...';
      _lastResultPreview = null;
    });

    appState.processingState = ProcessingState.processing;
    // ignore: deprecated_member_use
    SemanticsService.announce('Identifying currency', TextDirection.ltr);
    await tts.speak('Hold the note in front of the camera. Identifying currency.');

    try {
      final Uint8List frameBytes = await _captureFrame();
      if (!mounted) return;

      String result;
      if (useOnDevice) {
        final orchestrator = _getOrchestrator();
        if (!orchestrator.visionService.isReady) {
          setState(() => _statusMessage = 'Loading on-device AI model...');
          await tts.speak('Loading AI model. This may take a moment.');
        }
        result = await orchestrator.identifyCurrency(frameBytes);
      } else {
        final CurrencyDetectorService service =
            _getCurrencyService(settings.apiKey);
        result = await service.identifyCurrency(frameBytes);
      }
      if (!mounted) return;

      HapticFeedback.heavyImpact();
      setState(() {
        _statusMessage = 'Currency identified';
        _lastResultPreview = result;
      });

      appState.processingState = ProcessingState.speaking;
      await tts.speak(result);
    } catch (error) {
      if (!mounted) return;
      debugPrint('Currency error: $error');
      setState(() => _statusMessage = 'Currency detection failed.');
      appState.processingState = ProcessingState.speaking;
      await tts.speak('Unable to identify currency. Please try again.');
    } finally {
      appState.processingState = ProcessingState.idle;
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Brightness / Light Detection
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _onBrightnessTap() async {
    if (_isProcessing) return;
    HapticFeedback.mediumImpact();

    final TtsService tts = context.read<TtsService>();
    final AppStateProvider appState = context.read<AppStateProvider>();

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Checking brightness...';
      _lastResultPreview = null;
    });

    appState.processingState = ProcessingState.processing;
    // ignore: deprecated_member_use
    SemanticsService.announce('Checking brightness', TextDirection.ltr);

    try {
      final Uint8List frameBytes = await _captureFrame();
      if (!mounted) return;

      final BrightnessResult result =
          _brightnessService.analyseFromBytes(frameBytes);

      HapticFeedback.mediumImpact();
      setState(() {
        _statusMessage = 'Brightness: ${result.label}';
        _lastResultPreview = result.description;
      });

      appState.processingState = ProcessingState.speaking;
      await tts.speak(result.description);
    } catch (error) {
      if (!mounted) return;
      debugPrint('Brightness error: $error');
      setState(() => _statusMessage = 'Brightness check failed.');
      appState.processingState = ProcessingState.speaking;
      await tts.speak('Unable to check brightness. Please try again.');
    } finally {
      appState.processingState = ProcessingState.idle;
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // People Detection (Face + Pose)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _onPeopleTap() async {
    if (_isProcessing) return;
    HapticFeedback.mediumImpact();

    final TtsService tts = context.read<TtsService>();
    final AppStateProvider appState = context.read<AppStateProvider>();

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Looking for people...';
      _lastResultPreview = null;
    });

    appState.processingState = ProcessingState.processing;
    // ignore: deprecated_member_use
    SemanticsService.announce('Looking for people', TextDirection.ltr);

    File? tempFile;
    try {
      final Uint8List frameBytes = await _captureFrame();
      if (!mounted) return;

      final Directory tempDir = await getTemporaryDirectory();
      tempFile = File('${tempDir.path}/lumisense_people.jpg');
      await tempFile.writeAsBytes(frameBytes);

      // Run face detection and pose detection concurrently.
      _faceDetectionService ??= FaceDetectionService();
      _poseDetectionService ??= PoseDetectionService();

      final results = await Future.wait(<Future<Object>>[
        _faceDetectionService!.detectFromFile(tempFile.path),
        _poseDetectionService!.detectFromFile(tempFile.path),
      ]);

      if (!mounted) return;

      final FaceDetectionResult faceResult =
          results[0] as FaceDetectionResult;
      final PoseDetectionResult poseResult =
          results[1] as PoseDetectionResult;

      // Combine results: prefer face detection description, enrich with pose.
      String description;
      if (faceResult.faceCount == 0 && poseResult.poseCount == 0) {
        description =
            'No people detected. There does not appear to be anyone in front of you.';
      } else if (faceResult.faceCount > 0) {
        description = faceResult.description;
        // Add pose info if it adds new detail.
        if (poseResult.poseCount > 0) {
          // Extract just the posture/gesture parts from pose description.
          final String poseExtra = poseResult.description;
          if (poseExtra.contains('standing') ||
              poseExtra.contains('sitting') ||
              poseExtra.contains('raising') ||
              poseExtra.contains('arms raised')) {
            description += ' $poseExtra';
          }
        }
      } else {
        description = poseResult.description;
      }

      HapticFeedback.mediumImpact();
      setState(() {
        _statusMessage =
            '${faceResult.faceCount} face(s) detected';
        _lastResultPreview = description;
      });

      appState.processingState = ProcessingState.speaking;
      await tts.speak(description);
    } catch (error) {
      if (!mounted) return;
      debugPrint('People detection error: $error');
      setState(() => _statusMessage = 'People detection failed.');
      appState.processingState = ProcessingState.speaking;
      await tts.speak('Unable to detect people. Please try again.');
    } finally {
      appState.processingState = ProcessingState.idle;
      if (mounted) setState(() => _isProcessing = false);
      tempFile?.delete().ignore();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Weather Check
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _onWeatherTap() async {
    if (_isProcessing) return;
    HapticFeedback.mediumImpact();

    final TtsService tts = context.read<TtsService>();
    final SettingsProvider settings = context.read<SettingsProvider>();
    final AppStateProvider appState = context.read<AppStateProvider>();

    if (!settings.hasWeatherApiKey) {
      HapticFeedback.heavyImpact();
      await tts.speak(
        'No weather API key configured. '
        'Please add your free OpenWeatherMap key in Settings.',
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Checking weather...';
      _lastResultPreview = null;
    });

    appState.processingState = ProcessingState.processing;
    // ignore: deprecated_member_use
    SemanticsService.announce('Checking weather', TextDirection.ltr);
    await tts.speak('Fetching weather information.');

    try {
      final WeatherInfo? weather = await _weatherService.getCurrentWeatherByGps(
        apiKey: settings.weatherApiKey,
      );
      if (!mounted) return;

      if (weather == null) {
        HapticFeedback.heavyImpact();
        setState(() {
          _statusMessage = 'Weather unavailable';
          _lastResultPreview =
              'Could not fetch weather. Check your internet connection and location permissions.';
        });
        appState.processingState = ProcessingState.speaking;
        await tts.speak(
          'Unable to fetch weather data. Please check your internet connection '
          'and make sure location is enabled.',
        );
        return;
      }

      HapticFeedback.mediumImpact();
      setState(() {
        _statusMessage =
            '${weather.cityName}: ${weather.temperature.round()}°C, ${weather.description}';
        _lastResultPreview = weather.spokenSummary;
      });

      appState.processingState = ProcessingState.speaking;
      await tts.speak(weather.spokenSummary);
    } catch (error) {
      if (!mounted) return;
      debugPrint('Weather error: $error');
      setState(() => _statusMessage = 'Weather check failed.');
      appState.processingState = ProcessingState.speaking;
      await tts.speak('Unable to check weather. Please try again.');
    } finally {
      appState.processingState = ProcessingState.idle;
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Voice-Based Contact Calling
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _onCallContactTap(String rawText) async {
    if (_isProcessing) return;
    HapticFeedback.mediumImpact();

    final TtsService tts = context.read<TtsService>();
    final AppStateProvider appState = context.read<AppStateProvider>();

    final String contactName = SttService.extractContactName(rawText);
    if (contactName.isEmpty) {
      await tts.speak('Please say "call" followed by a contact name.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Searching contacts for "$contactName"...';
      _lastResultPreview = null;
    });

    appState.processingState = ProcessingState.processing;
    // ignore: deprecated_member_use
    SemanticsService.announce(
        'Searching contacts for $contactName', TextDirection.ltr);
    await tts.speak('Searching contacts for $contactName.');

    try {
      final ContactSearchResult result =
          await _contactCallerService.searchAndPrepareCall(contactName);
      if (!mounted) return;

      if (!result.found) {
        HapticFeedback.heavyImpact();
        setState(() {
          _statusMessage = 'Contact not found';
          _lastResultPreview =
              'No contact named "$contactName" found on your phone.';
        });
        appState.processingState = ProcessingState.speaking;
        await tts.speak(
          'No contact named $contactName found. '
          'Please check the name and try again.',
        );
        return;
      }

      if (result.phoneNumber == null) {
        HapticFeedback.heavyImpact();
        setState(() {
          _statusMessage = 'No phone number';
          _lastResultPreview =
              '${result.displayName} has no phone number saved.';
        });
        appState.processingState = ProcessingState.speaking;
        await tts.speak(
          '${result.displayName} does not have a phone number saved.',
        );
        return;
      }

      HapticFeedback.heavyImpact();
      setState(() {
        _statusMessage = 'Calling ${result.displayName}';
        _lastResultPreview = result.spokenSummary;
      });

      appState.processingState = ProcessingState.speaking;
      await tts.speak(result.spokenSummary);

      // Brief delay so user hears the confirmation.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final bool launched =
          await _contactCallerService.dialNumber(result.phoneNumber!);
      if (!launched && mounted) {
        await tts.speak('Could not open the phone app. Please try manually.');
      }
    } catch (error) {
      if (!mounted) return;
      debugPrint('Contact call error: $error');
      setState(() => _statusMessage = 'Contact search failed.');
      appState.processingState = ProcessingState.speaking;
      await tts.speak('Unable to search contacts. Please try again.');
    } finally {
      appState.processingState = ProcessingState.idle;
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Shows a dialog for the user to type or speak a contact name for calling.
  void _showCallDialog() {
    HapticFeedback.mediumImpact();
    final TextEditingController nameController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppTheme.cardBackground,
          title: const Text(
            'Call Contact',
            style: TextStyle(color: AppTheme.textPrimary),
          ),
          content: Semantics(
            label: 'Enter contact name to call',
            textField: true,
            child: TextField(
              controller: nameController,
              autofocus: true,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18),
              decoration: InputDecoration(
                hintText: 'Contact name (e.g. Mom)',
                filled: true,
                fillColor: AppTheme.darkBackground,
                prefixIcon:
                    const Icon(Icons.person, color: AppTheme.accentBlue),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: AppTheme.accentBlue, width: 2),
                ),
              ),
              textInputAction: TextInputAction.go,
              onSubmitted: (String value) {
                Navigator.of(dialogContext).pop();
                if (value.trim().isNotEmpty) {
                  _onCallContactTap('call ${value.trim()}');
                }
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                final String name = nameController.text.trim();
                if (name.isNotEmpty) {
                  _onCallContactTap('call $name');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Call'),
            ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UPI QR Payment Scan
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _onPayTap() async {
    if (_isProcessing) return;
    HapticFeedback.mediumImpact();

    final TtsService tts = context.read<TtsService>();
    final AppStateProvider appState = context.read<AppStateProvider>();

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Scanning for QR code...';
      _lastResultPreview = null;
    });

    appState.processingState = ProcessingState.processing;
    // ignore: deprecated_member_use
    SemanticsService.announce('Scanning for payment QR code', TextDirection.ltr);
    await tts.speak('Scanning for payment QR code. Point the camera at a QR code.');

    // Take multiple attempts with short delays to give the user time to aim.
    const int maxAttempts = 6;
    const Duration attemptDelay = Duration(milliseconds: 800);

    File? tempFile;
    QrScanResult? scanResult;

    try {
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        if (!mounted) return;

        final Uint8List frameBytes = await _captureFrame();
        if (!mounted) return;

        final Directory tempDir = await getTemporaryDirectory();
        tempFile = File('${tempDir.path}/lumisense_qr_capture.jpg');
        await tempFile.writeAsBytes(frameBytes);

        scanResult = await _qrScannerService.scanFromImagePath(tempFile.path);

        if (scanResult.found) break;

        // Brief delay before next attempt.
        if (attempt < maxAttempts) {
          await Future<void>.delayed(attemptDelay);
        }
      }

      if (!mounted) return;

      if (scanResult == null || !scanResult.found) {
        setState(() {
          _statusMessage = 'No QR code found';
          _lastResultPreview = 'Point the camera at a QR code and try again.';
        });
        HapticFeedback.heavyImpact();
        appState.processingState = ProcessingState.speaking;
        await tts.speak(
          'No QR code detected. Please point the camera directly at a QR code and try again.',
        );
        return;
      }

      // QR found!
      HapticFeedback.mediumImpact();

      if (scanResult.isUpi) {
        final UpiPaymentInfo upi = scanResult.upiInfo!;

        setState(() {
          _statusMessage = 'UPI Payment QR detected';
          _lastResultPreview = upi.spokenSummary;
        });

        appState.processingState = ProcessingState.speaking;
        await tts.speak('${upi.spokenSummary}. Opening payment app.');

        // Brief delay so user hears the confirmation.
        await Future<void>.delayed(const Duration(milliseconds: 600));

        final bool launched = await _upiPaymentService.launchPayment(upi);
        if (!launched && mounted) {
          HapticFeedback.heavyImpact();
          await tts.speak(
            'Could not open a UPI payment app. '
            'Please make sure Google Pay, PhonePe, or another UPI app is installed.',
          );
        }
      } else {
        // Non-UPI QR code — just read out the content.
        setState(() {
          _statusMessage = 'QR code scanned';
          _lastResultPreview = scanResult!.rawValue ?? 'Empty QR code';
        });

        appState.processingState = ProcessingState.speaking;
        await tts.speak(
          'QR code found, but it is not a UPI payment code. '
          'Content: ${scanResult.rawValue ?? "empty"}',
        );
      }
    } catch (error) {
      if (!mounted) return;
      debugPrint('QR scan error: $error');
      setState(() => _statusMessage = 'QR scan failed. Please try again.');
      appState.processingState = ProcessingState.speaking;
      await tts.speak('Unable to scan QR code right now. Please try again.');
    } finally {
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      appState.processingState = ProcessingState.idle;
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SOS — with countdown and cancel
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _onSosTap() async {
    HapticFeedback.vibrate();
    final TtsService tts = context.read<TtsService>();
    final SettingsProvider settings = context.read<SettingsProvider>();

    if (!settings.hasEmergencyContact) {
      await tts.speakUrgent(
          'No emergency contact set. Please add one in Settings.');
      return;
    }

    // If already counting down, cancel.
    if (_sosPending) {
      _sosPending = false;
      HapticFeedback.mediumImpact();
      await tts.speakUrgent('SOS cancelled.');
      return;
    }

    // Start countdown.
    _sosPending = true;
    await tts.speakUrgent(
        'Emergency SOS in $_sosCountdownSeconds seconds. Tap SOS again or say stop to cancel.');

    for (int i = _sosCountdownSeconds; i > 0; i--) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!_sosPending || !mounted) {
        // Cancelled during countdown.
        return;
      }
      HapticFeedback.heavyImpact();
    }

    if (!_sosPending || !mounted) return;
    _sosPending = false;

    // Actually send SOS.
    // ignore: deprecated_member_use
    SemanticsService.announce('Sending emergency message', TextDirection.ltr);
    await tts.speakUrgent('Sending emergency message now.');

    try {
      final SosResult result =
          await SosService.sendEmergencySms(settings.emergencyContact);
      if (mounted) {
        await tts.speak(result.message);
      }
    } catch (e) {
      debugPrint('SOS error: $e');
      if (mounted) {
        await tts.speakUrgent(
            'Emergency message failed. Please try calling for help.');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_cameraError != null && !_hasPermission) {
      return Scaffold(
        backgroundColor: AppTheme.darkBackground,
        body: _buildErrorState(context, _cameraError!),
      );
    }

    if (!_hasPermission) {
      return const Scaffold(
        backgroundColor: AppTheme.darkBackground,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.accentBlue),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: Stack(
        children: <Widget>[
          // Camera + inference
          Positioned.fill(
            child: GestureDetector(
              onTap: _isNavigating ? null : _onDescribeTap,
              child: YOLOView(
                modelPath: 'yolo11n.tflite',
                task: YOLOTask.detect,
                controller: _yoloController,
                onResult: _onYoloResult,
                onPerformanceMetrics: _onPerformanceMetrics,
                showOverlays: false,
                confidenceThreshold: 0.25,
                iouThreshold: 0.45,
              ),
            ),
          ),

          // Bounding box overlay — excluded from screen reader
          if (_isNavigating && _lastDetections.isNotEmpty)
            Positioned.fill(
              child: ExcludeSemantics(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    return BoundingBoxOverlay(
                      detections: _lastDetections,
                      previewSize: Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      ),
                    );
                  },
                ),
              ),
            ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Semantics(
              sortKey: const OrdinalSortKey(0),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: <Widget>[
                      _buildTopButton(
                        icon: Icons.arrow_back,
                        label: 'Go back',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      if (_directionsService?.isNavigating ?? false)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.accentBlue.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(Icons.directions_walk,
                                  color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                'Step ${(_directionsService!.currentStepIndex + 1)}/${_directionsService!.route?.steps.length ?? 0}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_isNavigating)
                        NavigationModeIndicator(
                          isActive: _isNavigating,
                          detectionCount: _lastDetections.length,
                          fps: _navFps,
                        ),
                      if (!_isNavigating && _isListening)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _sttService.continuousMode
                                ? Colors.green.shade700.withValues(alpha: 0.8)
                                : AppTheme.error.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(Icons.mic, color: Colors.white, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                _sttService.continuousMode
                                    ? 'Always listening'
                                    : 'Listening...',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12)),
                            ],
                          ),
                        ),
                      if (!_isNavigating && !_isListening)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _yoloTimedOut
                                ? 'Camera (detection slow)'
                                : 'Live Camera',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      const SizedBox(width: 8),
                      _buildTopButton(
                        icon: _sttService.continuousMode
                            ? (_isListening ? Icons.mic : Icons.hearing)
                            : Icons.mic_off,
                        label: _sttService.continuousMode
                            ? (_isListening ? 'Listening' : 'Waiting...')
                            : 'Mic off',
                        onPressed: _toggleListening,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom controls
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (_statusMessage != null ||
                      _lastResultPreview != null)
                    Semantics(
                      sortKey: const OrdinalSortKey(1),
                      child: _buildResultPanel(),
                    ),
                  Semantics(
                    sortKey: const OrdinalSortKey(2),
                    child: _buildActionBar(),
                  ),
                  const SizedBox(height: 10),
                  Semantics(
                    sortKey: const OrdinalSortKey(3),
                    child: _buildSosButton(),
                  ),
                ],
              ),
            ),
          ),

          // ── Directions panel overlay ──────────────────────────────────
          if (_showDirectionsPanel)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Semantics(
                sortKey: const OrdinalSortKey(0.5),
                child: DirectionsPanel(
                  directionsService: _directionsService,
                  onNavigate: (String dest) {
                    _startTurnByTurnNavigation(dest);
                  },
                  onStop: () {
                    _stopTurnByTurnNavigation();
                    context.read<TtsService>().speak('Walking directions stopped.');
                    setState(() => _showDirectionsPanel = false);
                  },
                  onOpenMap: _openRouteMap,
                  onRepeat: () {
                    HapticFeedback.lightImpact();
                    _directionsService?.repeatCurrentStep();
                  },
                  onStatus: () {
                    HapticFeedback.lightImpact();
                    _directionsService?.announceStatus();
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Top button ───────────────────────────────────────────────────────────

  Widget _buildTopButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Semantics(
      label: label,
      button: true,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            onPressed();
          },
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(icon, color: Colors.white)),
        ),
      ),
    );
  }

  // ─── Action bar ───────────────────────────────────────────────────────────

  Widget _buildActionBar() {
    final bool hasActiveDirections = _directionsService?.isActive ?? false;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Primary actions row
          Row(
            children: <Widget>[
              Expanded(
                child: _buildActionButton(
                  icon: Icons.text_fields,
                  label: 'Read',
                  onPressed: _onReadTap,
                  enabled: !_isProcessing,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.search,
                  label: 'Identify',
                  onPressed: _onIdentifyTap,
                  enabled: !_isProcessing && _yoloViewReady,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: _isNavigating
                      ? Icons.navigation
                      : Icons.navigation_outlined,
                  label: _isNavigating ? 'Stop Nav' : 'Navigate',
                  onPressed: _toggleNavigation,
                  highlighted: _isNavigating,
                  enabled: !_isProcessing && _yoloViewReady,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.auto_awesome,
                  label: 'Describe',
                  onPressed: _onDescribeTap,
                  enabled: !_isProcessing,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Directions + Pay row
          Row(
            children: <Widget>[
              // Pay / Scan QR button
              Expanded(
                flex: 2,
                child: _buildActionButton(
                  icon: Icons.qr_code_scanner,
                  label: 'Pay',
                  onPressed: _onPayTap,
                  enabled: !_isProcessing,
                ),
              ),
              const SizedBox(width: 8),
              // Directions button — opens the input/navigation panel
              Expanded(
                flex: 3,
                child: _buildActionButton(
                  icon: hasActiveDirections
                      ? Icons.directions_walk
                      : Icons.directions,
                  label: hasActiveDirections ? 'Directions ●' : 'Directions',
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    setState(() =>
                        _showDirectionsPanel = !_showDirectionsPanel);
                  },
                  highlighted: _showDirectionsPanel || hasActiveDirections,
                  enabled: true,
                ),
              ),
              if (hasActiveDirections) ...<Widget>[
                const SizedBox(width: 8),
                // Quick map button
                Expanded(
                  flex: 2,
                  child: _buildActionButton(
                    icon: Icons.map,
                    label: 'Map',
                    onPressed: _openRouteMap,
                    enabled: true,
                  ),
                ),
                const SizedBox(width: 8),
                // Quick stop button
                Expanded(
                  flex: 2,
                  child: _buildActionButton(
                    icon: Icons.stop_circle,
                    label: 'Stop Dir.',
                    onPressed: () {
                      HapticFeedback.heavyImpact();
                      _stopTurnByTurnNavigation();
                      context.read<TtsService>().speak('Walking directions stopped.');
                      setState(() => _showDirectionsPanel = false);
                    },
                    enabled: true,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Utility tools row
          Row(
            children: <Widget>[
              Expanded(
                child: _buildActionButton(
                  icon: Icons.currency_rupee,
                  label: 'Currency',
                  onPressed: _onCurrencyTap,
                  enabled: !_isProcessing,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.people,
                  label: 'People',
                  onPressed: _onPeopleTap,
                  enabled: !_isProcessing,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.light_mode,
                  label: 'Light',
                  onPressed: _onBrightnessTap,
                  enabled: !_isProcessing,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.cloud,
                  label: 'Weather',
                  onPressed: _onWeatherTap,
                  enabled: !_isProcessing,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.phone,
                  label: 'Call',
                  onPressed: () => _showCallDialog(),
                  enabled: !_isProcessing,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool highlighted = false,
    bool enabled = true,
  }) {
    final Color background =
        highlighted ? AppTheme.accentBlue : AppTheme.cardBackground;
    final Color foreground =
        highlighted ? AppTheme.darkBackground : AppTheme.textPrimary;

    return Semantics(
      label: label,
      button: true,
      child: SizedBox(
        height: 72,
        child: ElevatedButton(
          onPressed: enabled
              ? () {
                  HapticFeedback.mediumImpact();
                  onPressed();
                }
              : null,
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: background,
            foregroundColor: foreground,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 24),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── SOS button ───────────────────────────────────────────────────────────

  Widget _buildSosButton() {
    return Semantics(
      label: _sosPending
          ? 'Cancel SOS countdown. Tap to cancel.'
          : 'Emergency SOS. Double tap to send your location to your emergency contact.',
      button: true,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton.icon(
          onPressed: _onSosTap,
          icon: Icon(_sosPending ? Icons.cancel : Icons.sos, size: 24),
          label: Text(
            _sosPending ? 'CANCEL SOS' : 'SOS',
            style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _sosPending ? AppTheme.warning : AppTheme.error,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Result panel ─────────────────────────────────────────────────────────

  Widget _buildResultPanel() {
    final String? preview = _lastResultPreview;

    return Semantics(
      liveRegion: true,
      label: preview ?? _statusMessage ?? '',
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: AppTheme.textHint.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_statusMessage != null)
              Text(
                _statusMessage!,
                style: const TextStyle(
                  color: AppTheme.accentBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (preview != null && preview.isNotEmpty) ...<Widget>[
              if (_statusMessage != null) const SizedBox(height: 6),
              Text(
                preview,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Error state ──────────────────────────────────────────────────────────

  Widget _buildErrorState(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.camera_alt_outlined,
                color: AppTheme.error, size: 56),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 20),
            Semantics(
              label: 'Retry camera',
              button: true,
              child: SizedBox(
                height: 72,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.heavyImpact();
                    setState(() => _cameraError = null);
                    _ensureCameraPermission();
                  },
                  child: const Text('Retry Camera'),
                ),
              ),
            ),
            if (_permissionPermanentlyDenied) ...<Widget>[
              const SizedBox(height: 12),
              Semantics(
                label: 'Open device settings',
                button: true,
                child: SizedBox(
                  height: 72,
                  child: OutlinedButton(
                    onPressed: _openAppSettings,
                    child: const Text('Open Settings'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Voice command toggle ─────────────────────────────────────────────────

  Future<void> _toggleListening() async {
    HapticFeedback.mediumImpact();
    if (_sttService.continuousMode) {
      // Turn off continuous listening
      await _sttService.stopListening();
      if (mounted) setState(() {});
    } else {
      // Turn on continuous listening
      await context.read<TtsService>().stop();
      _sttService.setContinuousMode(true);
      await _sttService.startListening();
      if (mounted) setState(() {});
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Reads long text in manageable chunks using [speakAndWait].
  /// Respects the [TtsService.chunkReadingCancelled] flag for interruption.
  Future<void> _speakTextInChunks(TtsService tts, String text) async {
    final String normalized = text.replaceAll('\n', ' ').trim();
    if (normalized.isEmpty) return;

    tts.chunkReadingCancelled = false;

    final List<String> chunks = <String>[];
    int start = 0;
    while (start < normalized.length) {
      int end = (start + _chunkSize).clamp(0, normalized.length);
      if (end < normalized.length) {
        final int lastPeriod = normalized.lastIndexOf('.', end);
        final int lastSpace = normalized.lastIndexOf(' ', end);
        final int splitAt = lastPeriod > start + 80
            ? lastPeriod + 1
            : (lastSpace > start + 60 ? lastSpace : end);
        end = splitAt;
      }
      chunks.add(normalized.substring(start, end).trim());
      start = end;
    }

    final List<String> nonEmpty =
        chunks.where((String c) => c.isNotEmpty).toList();

    // Announce part count for multi-chunk text.
    if (nonEmpty.length > 1) {
      await tts.speakAndWait('Reading ${nonEmpty.length} parts.');
      if (tts.chunkReadingCancelled) return;
    }

    for (final String chunk in nonEmpty) {
      if (tts.chunkReadingCancelled) return;
      await tts.speakAndWait(chunk);
    }
  }

  bool get _powerReadMode => context.read<SettingsProvider>().powerReadMode;

  GeminiService _getGeminiService(SettingsProvider settings) {
    final String apiKey = settings.apiKey;
    final String orKey = settings.openRouterApiKey;
    final String groqKey = settings.groqApiKey;
    final String ollamaUrl = settings.ollamaServerUrl;

    if (_geminiService == null ||
        _geminiApiKey != apiKey ||
        _openRouterApiKey != orKey) {
      _geminiService = GeminiService(
        apiKey: apiKey,
        openRouterApiKey: orKey,
        groqApiKey: groqKey,
        ollamaServerUrl: ollamaUrl,
      );
      _geminiApiKey = apiKey;
      _openRouterApiKey = orKey;
    }
    return _geminiService!;
  }

  /// Returns the on-device orchestrator, creating it lazily.
  OnDeviceOrchestrator _getOrchestrator() {
    if (_onDeviceOrchestrator == null) {
      final modelMgr = context.read<ModelManager>();
      _onDeviceOrchestrator = OnDeviceOrchestrator(modelManager: modelMgr);
    }
    return _onDeviceOrchestrator!;
  }

  /// Whether to use on-device models for the current operation.
  /// Returns true only if enabled in settings AND the vision model is ready.
  Future<bool> _shouldUseOnDevice() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.useOnDeviceModels) return false;
    final orchestrator = _getOrchestrator();
    return orchestrator.visionService.isReady ||
        await orchestrator.isVisionModelReady;
  }

  void _triggerInitialActionIfNeeded() {
    if (_initialActionTriggered) return;
    if (widget.initialAction == CameraInitialAction.none) return;
    if (!_yoloViewReady) return;

    _initialActionTriggered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isProcessing) return;
      switch (widget.initialAction) {
        case CameraInitialAction.read:
          unawaited(_onReadTap());
        case CameraInitialAction.identify:
          unawaited(_onIdentifyTap());
        case CameraInitialAction.describe:
          unawaited(_onDescribeTap());
        case CameraInitialAction.navigate:
          if (_yoloViewReady) {
            _toggleNavigation();
          } else {
            _pendingInitialNavigateRetry = true;
          }
        case CameraInitialAction.scanPayment:
          unawaited(_onPayTap());
        case CameraInitialAction.identifyCurrency:
          unawaited(_onCurrencyTap());
        case CameraInitialAction.checkBrightness:
          unawaited(_onBrightnessTap());
        case CameraInitialAction.checkWeather:
          unawaited(_onWeatherTap());
        case CameraInitialAction.detectPeople:
          unawaited(_onPeopleTap());
        case CameraInitialAction.none:
          break;
      }
    });
  }

  void _retryPendingInitialNavigate() {
    if (!_pendingInitialNavigateRetry) return;
    if (!_yoloViewReady || _isProcessing) return;
    if (!mounted || _isNavigating) return;

    _pendingInitialNavigateRetry = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isProcessing || _isNavigating) return;
      _toggleNavigation();
    });
  }
}
