import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lumisense/models/history_entry.dart';
import 'package:lumisense/models/ocr_result.dart';
import 'package:lumisense/providers/app_state.dart';
import 'package:lumisense/providers/history_provider.dart';
import 'package:lumisense/providers/settings_provider.dart';
import 'package:lumisense/services/camera_service.dart';
import 'package:lumisense/services/gemini_service.dart';
import 'package:lumisense/services/navigation_mode_controller.dart';
import 'package:lumisense/services/ocr_service.dart';
import 'package:lumisense/services/sos_service.dart';
import 'package:lumisense/services/stt_service.dart';
import 'package:lumisense/services/tts_service.dart';
import 'package:lumisense/services/yolo_service.dart';
import 'package:lumisense/utils/image_utils.dart';
import 'package:lumisense/utils/theme.dart';
import 'package:lumisense/widgets/bounding_box_overlay.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

/// Specifies an action to auto-trigger when the camera screen opens.
///
/// Used by the home screen quick-access buttons so blind users don't
/// have to navigate to the camera and tap a second time.
enum CameraInitialAction { none, read, identify, describe, navigate }

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
  final CameraService _cameraService = CameraService();
  final OcrService _ocrService = OcrService();
  final YoloService _yoloService = YoloService();
  final SttService _sttService = SttService();

  late final NavigationModeController _navController;
  GeminiService? _geminiService;
  String? _geminiApiKey;

  late Future<void> _cameraInitialization;
  String? _cameraError;
  String? _statusMessage;
  String? _lastResultPreview;
  bool _cameraPermissionPermanentlyDenied = false;
  bool _isProcessing = false;
  bool _isListening = false;
  bool _initialActionTriggered = false;
  bool _pendingInitialNavigateRetry = false;
  Future<void>? _lifecycleShutdownFuture;

  // ─── Navigation mode state ─────────────────────────────────────────────────

  bool _isNavigating = false;
  bool _isYoloReady = false;
  bool _isInferring = false;
  List<YoloDetection> _yoloDetections = const [];
  int _cameraImageWidth = 0;
  int _cameraImageHeight = 0;
  double _navFps = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _navController = NavigationModeController(tts: context.read<TtsService>());
    _cameraInitialization = _initializeCamera();
    _initStt();
    _initYolo();
  }

  Future<void> _initStt() async {
    await _sttService.init();
    _sttService.onCommand = _handleVoiceCommand;
    _sttService.onListeningChanged = (bool listening) {
      if (mounted) setState(() => _isListening = listening);
    };
  }

  /// Pre-load the YOLO model in background so navigation mode starts instantly.
  Future<void> _initYolo() async {
    try {
      await _yoloService.loadModel(useGpu: true, numThreads: 2);
      if (mounted) {
        setState(() => _isYoloReady = true);
      }
      _retryPendingInitialNavigate();
    } catch (e) {
      debugPrint('YOLO model load failed: $e');
      // Navigation mode will be unavailable but all other features work.
    }
  }

  void _handleVoiceCommand(VoiceCommand command, String rawText) {
    if (_isProcessing) return;

    switch (command) {
      case VoiceCommand.readText:
        _onReadTap();
      case VoiceCommand.identifyObjects:
        _onIdentifyTap();
      case VoiceCommand.describeScene:
        _onDescribeTap();
      case VoiceCommand.navigation:
        _toggleNavigation();
      case VoiceCommand.help:
        context.read<TtsService>().speak(SttService.helpText);
      case VoiceCommand.sos:
        _onSosTap();
      case VoiceCommand.stop:
        context.read<TtsService>().stop();
      case VoiceCommand.unknown:
        context
            .read<TtsService>()
            .speak('I did not understand that command. Say help for options.');
    }
  }

  Future<void> _initializeCamera() async {
    final bool hasPermission = await _ensureCameraPermission();
    if (!hasPermission) return;

    try {
      await _cameraService.initialize();
      if (!mounted) return;
      setState(() {
        _cameraError = null;
        _cameraPermissionPermanentlyDenied = false;
      });
      _triggerInitialActionIfNeeded();
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = _friendlyCameraError(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _cameraError = 'Unable to initialize the camera.');
    }
  }

  Future<bool> _ensureCameraPermission() async {
    PermissionStatus status = await Permission.camera.status;
    if (status.isGranted) return true;

    status = await Permission.camera.request();
    if (status.isGranted) return true;
    if (!mounted) return false;

    final bool permanentlyDenied =
        status.isPermanentlyDenied || status.isRestricted;

    setState(() {
      _cameraPermissionPermanentlyDenied = permanentlyDenied;
      _cameraError = permanentlyDenied
          ? 'Camera permission is blocked. Open settings to enable camera access.'
          : 'Camera permission denied. Allow camera access to continue.';
    });

    return false;
  }

  Future<void> _openAppSettings() async {
    await openAppSettings();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      unawaited(_serializeLifecycleShutdown());
      return;
    }

    if (state == AppLifecycleState.resumed) {
      setState(() => _cameraInitialization = _initializeCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_serializeLifecycleShutdown());
    unawaited(_ocrService.dispose());
    unawaited(_sttService.dispose());
    _navController.dispose();
    // Don't dispose YoloService — it's a singleton shared across the app.
    super.dispose();
  }

  // ─── Navigation Mode ──────────────────────────────────────────────────────

  void _toggleNavigation() {
    if (!_isYoloReady) {
      context.read<TtsService>().speak(
        'Navigation mode is not available. The YOLO model could not be loaded.',
      );
      return;
    }

    if (_isNavigating) {
      unawaited(_stopNavigation(announce: true));
    } else {
      unawaited(_startNavigation());
    }
  }

  Future<void> _startNavigation() async {
    if (_isNavigating || !_isYoloReady) return;
    if (!_cameraService.isInitialized) return;

    final TtsService tts = context.read<TtsService>();
    final AppStateProvider appState = context.read<AppStateProvider>();

    setState(() {
      _isNavigating = true;
      _yoloDetections = const [];
      _statusMessage = 'Navigation mode active';
      _lastResultPreview = 'Scanning surroundings...';
    });

    appState.currentMode = AppMode.navigation;
    HapticFeedback.mediumImpact();
    await tts.speak('Navigation mode on.');

    // Start camera image stream → feed YOLO.
    await _cameraService.startImageStream(_onCameraFrame);
  }

  Future<void> _stopNavigation({bool announce = true}) async {
    if (!_isNavigating) return;
    final TtsService? tts = announce ? context.read<TtsService>() : null;

    await _cameraService.stopImageStream();
    _navController.reset();

    if (mounted) {
      setState(() {
        _isNavigating = false;
        _isInferring = false;
        _yoloDetections = const [];
        _navFps = 0;
        _statusMessage = null;
        _lastResultPreview = null;
      });
    }

    if (announce && tts != null) {
      HapticFeedback.mediumImpact();
      await tts.speak('Navigation mode off.');
    }
  }

  /// Called for every camera frame while navigation mode is active.
  void _onCameraFrame(CameraImage image) {
    // Skip frame if already processing one — natural throttle to max inference speed.
    if (!_isNavigating || _isInferring) return;
    _isInferring = true;

    // Store camera image dimensions for bounding box scaling.
    _cameraImageWidth = image.width;
    _cameraImageHeight = image.height;

    _yoloService
        .detectOnFrame(image, confThreshold: 0.45, iouThreshold: 0.45)
        .then((List<YoloDetection> detections) {
      if (!mounted || !_isNavigating) {
        _isInferring = false;
        return;
      }

      // Update navigation controller (handles TTS announcements).
      _navController.updateDetections(detections);

      setState(() {
        _yoloDetections = detections;
        _navFps = _navController.fps;
        _isInferring = false;
      });
    }).catchError((Object error) {
      debugPrint('Navigation frame error: $error');
      _isInferring = false;
    });
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: FutureBuilder<void>(
        future: _cameraInitialization,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (_cameraError != null) {
            return _buildErrorState(context, _cameraError!);
          }

          if (snapshot.connectionState != ConnectionState.done ||
              !_cameraService.isInitialized) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryYellow),
            );
          }

          return Stack(
            children: <Widget>[
              // Camera preview — tap to describe
              Positioned.fill(
                child: Semantics(
                  label: 'Camera preview. Tap to describe the scene.',
                  child: GestureDetector(
                    onTap: _isNavigating ? null : _onDescribeTap,
                    child: CameraPreview(_cameraService.controller!),
                  ),
                ),
              ),

              // Bounding box overlay (navigation mode)
              if (_isNavigating && _yoloDetections.isNotEmpty)
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return BoundingBoxOverlay(
                        detections: _yoloDetections,
                        previewSize: Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ),
                        imageWidth: _cameraImageWidth,
                        imageHeight: _cameraImageHeight,
                      );
                    },
                  ),
                ),

              // Top bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: <Widget>[
                        _buildTopButton(
                          icon: Icons.arrow_back,
                          label: 'Back',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Spacer(),
                        // Navigation mode indicator
                        if (_isNavigating)
                          NavigationModeIndicator(
                            isActive: _isNavigating,
                            detectionCount: _yoloDetections.length,
                            fps: _navFps,
                          ),
                        // Listening indicator
                        if (!_isNavigating && _isListening)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.error.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(Icons.mic, color: Colors.white, size: 16),
                                SizedBox(width: 4),
                                Text('Listening...',
                                    style: TextStyle(
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
                            child: const Text(
                              'Live Camera',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        const SizedBox(width: 8),
                        // Voice command button
                        _buildTopButton(
                          icon: _isListening ? Icons.mic_off : Icons.mic,
                          label:
                              _isListening ? 'Stop listening' : 'Voice command',
                          onPressed: _toggleListening,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom — result panel + action bar + SOS
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  minimum: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (_statusMessage != null ||
                          _lastResultPreview != null)
                        _buildResultPanel(),
                      _buildActionBar(),
                      const SizedBox(height: 10),
                      _buildSosButton(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Top button ──────────────────────────────────────────────────────────

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
          child: SizedBox(width: 48, height: 48, child: Icon(icon, color: Colors.white)),
        ),
      ),
    );
  }

  // ─── Action bar ──────────────────────────────────────────────────────────

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
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
              enabled: !_isProcessing,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildActionButton(
              icon: _isNavigating ? Icons.navigation : Icons.navigation_outlined,
              label: _isNavigating ? 'Stop Nav' : 'Navigate',
              onPressed: _toggleNavigation,
              highlighted: _isNavigating,
              enabled: !_isProcessing && _isYoloReady,
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
        highlighted ? AppTheme.primaryYellow : AppTheme.cardBackground;
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
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── SOS button ──────────────────────────────────────────────────────────

  Widget _buildSosButton() {
    return Semantics(
      label: 'Emergency SOS. Double tap to send your location to your emergency contact.',
      button: true,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton.icon(
          onPressed: _isProcessing ? null : _onSosTap,
          icon: const Icon(Icons.sos, size: 24),
          label: const Text('SOS',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.error,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Result panel ────────────────────────────────────────────────────────

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
                  color: AppTheme.primaryYellow,
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

  // ─── Error state ─────────────────────────────────────────────────────────

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
                    setState(() {
                      _cameraError = null;
                      _cameraInitialization = _initializeCamera();
                    });
                  },
                  child: const Text('Retry Camera'),
                ),
              ),
            ),
            if (_cameraPermissionPermanentlyDenied) ...<Widget>[
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

  // ─── Voice command toggle ────────────────────────────────────────────────

  Future<void> _toggleListening() async {
    HapticFeedback.mediumImpact();
    if (_isListening) {
      await _sttService.stopListening();
    } else {
      await context.read<TtsService>().stop();
      await _sttService.startListening();
    }
  }

  // ─── OCR ─────────────────────────────────────────────────────────────────

  Future<void> _onReadTap() async {
    if (_isProcessing) return;
    HapticFeedback.selectionClick();

    final TtsService tts = context.read<TtsService>();
    final AppStateProvider appState = context.read<AppStateProvider>();
    final HistoryProvider history = context.read<HistoryProvider>();

    // Pause navigation if active.
    final bool wasNavigating = _isNavigating;
    if (wasNavigating) await _cameraService.stopImageStream();

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Reading text...';
      _lastResultPreview = null;
    });

    appState.currentMode = AppMode.readText;
    appState.processingState = ProcessingState.processing;

    XFile? frame;
    try {
      frame = await _cameraService.captureStillImage();
      final OcrResult result =
          await _ocrService.extractTextFromImagePath(frame.path);

      final String spokenText = result.hasText
          ? result.text
          : 'No readable text detected. Please move closer and try again.';

      if (!mounted) return;

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
      setState(() => _statusMessage = 'OCR failed. Please try again.');
      appState.processingState = ProcessingState.speaking;
      await tts.speak('Unable to read text right now. Please try again.');
    } finally {
      if (frame != null) {
        final File capturedFile = File(frame.path);
        if (await capturedFile.exists()) await capturedFile.delete();
      }
      appState.processingState = ProcessingState.idle;
      if (mounted) setState(() => _isProcessing = false);
      // Resume navigation if it was active.
      if (wasNavigating && mounted) {
        await _cameraService.startImageStream(_onCameraFrame);
      }
    }
  }

  // ─── Object detection (YOLO single-shot) ────────────────────────────────

  Future<void> _onIdentifyTap() async {
    if (_isProcessing) return;
    HapticFeedback.selectionClick();

    final TtsService tts = context.read<TtsService>();
    final AppStateProvider appState = context.read<AppStateProvider>();
    final HistoryProvider history = context.read<HistoryProvider>();

    // Pause navigation if active.
    final bool wasNavigating = _isNavigating;
    if (wasNavigating) await _cameraService.stopImageStream();

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Identifying objects...';
      _lastResultPreview = null;
    });

    appState.currentMode = AppMode.identifyObjects;
    appState.processingState = ProcessingState.processing;

    try {
      // Use YOLO if available, otherwise report unavailable.
      if (!_yoloService.isReady) {
        if (!mounted) return;
        setState(() => _statusMessage = 'Object detection model not loaded.');
        await tts.speak('Object detection is not available. The model could not be loaded.');
        return;
      }

      // Read the image bytes and use yoloOnImage (via a temp image detection).
      // For single-shot, we use Gemini describe as a richer alternative when available,
      // but YOLO gives instant offline results.
      // Since yoloOnFrame needs CameraImage, we fall back to Gemini for still images.
      // Actually — let's capture a frame from the stream briefly for YOLO single-shot.
      final Completer<CameraImage> frameCompleter = Completer<CameraImage>();
      bool capturedOneFrame = false;

      await _cameraService.startImageStream((CameraImage image) {
        if (!capturedOneFrame && !frameCompleter.isCompleted) {
          capturedOneFrame = true;
          frameCompleter.complete(image);
        }
      });

      final CameraImage singleFrame =
          await frameCompleter.future.timeout(const Duration(seconds: 2));
      await _cameraService.stopImageStream();

      final List<YoloDetection> detections = await _yoloService.detectOnFrame(
        singleFrame,
        confThreshold: 0.40,
        iouThreshold: 0.45,
      ).timeout(const Duration(seconds: 3));

      final List<YoloDetection> filtered = detections
          .where((d) => d.confidence >= 0.50)
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
        final labels = filtered.map((e) => e.label).toSet().toList();
        spokenText = 'I found ${labels.join(', ')}.';
        previewText = filtered
            .map((e) =>
                '${e.label} (${(e.confidence * 100).toStringAsFixed(0)}%)')
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
    } on TimeoutException {
      await _cameraService.stopImageStream();
      if (!mounted) return;
      setState(() => _statusMessage = 'Detection timed out. Please try again.');
      appState.processingState = ProcessingState.speaking;
      await tts.speak('Object detection timed out. Please try again.');
    } catch (_) {
      await _cameraService.stopImageStream();
      if (!mounted) return;
      setState(
          () => _statusMessage = 'Object identification failed. Please try again.');
      appState.processingState = ProcessingState.speaking;
      await tts
          .speak('Unable to identify objects right now. Please try again.');
    } finally {
      appState.processingState = ProcessingState.idle;
      if (mounted) setState(() => _isProcessing = false);
      // Resume navigation if it was active.
      if (wasNavigating && mounted) {
        await _cameraService.startImageStream(_onCameraFrame);
      }
    }
  }

  // ─── Scene description (Gemini) ──────────────────────────────────────────

  Future<void> _onDescribeTap() async {
    if (_isProcessing) return;
    HapticFeedback.lightImpact();

    final TtsService tts = context.read<TtsService>();
    final AppStateProvider appState = context.read<AppStateProvider>();
    final HistoryProvider history = context.read<HistoryProvider>();
    final SettingsProvider settings = context.read<SettingsProvider>();

    if (!settings.hasApiKey) {
      HapticFeedback.heavyImpact();
      await tts.speak(
        'No Gemini API key configured. Please add your key in the Settings screen.',
      );
      return;
    }

    // Pause navigation if active.
    final bool wasNavigating = _isNavigating;
    if (wasNavigating) await _cameraService.stopImageStream();

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Describing scene...';
      _lastResultPreview = null;
    });

    appState.currentMode = AppMode.describeScene;
    appState.processingState = ProcessingState.processing;

    XFile? frame;
    try {
      frame = await _cameraService.captureStillImage();
      final bytes = await ImageUtils.readJpegBytes(frame.path);

      final GeminiService gemini = _getGeminiService(settings.apiKey);
      final String description = await gemini.describeScene(bytes);

      if (!mounted) return;

      setState(() {
        _statusMessage = 'Scene described';
        _lastResultPreview = description;
      });

      await history.addEntry(
        type: HistoryEntryType.sceneDescription,
        title: 'Scene Description',
        content: description,
      );

      appState.processingState = ProcessingState.speaking;
      await tts.speak(description);
    } on GeminiApiException catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Description failed.');
      appState.processingState = ProcessingState.speaking;
      await tts.speak(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Description failed. Please try again.');
      appState.processingState = ProcessingState.speaking;
      await tts.speak('Unable to describe the scene right now. Please try again.');
    } finally {
      if (frame != null) {
        final File capturedFile = File(frame.path);
        if (await capturedFile.exists()) await capturedFile.delete();
      }
      appState.processingState = ProcessingState.idle;
      if (mounted) setState(() => _isProcessing = false);
      // Resume navigation if it was active.
      if (wasNavigating && mounted) {
        await _cameraService.startImageStream(_onCameraFrame);
      }
    }
  }

  // ─── SOS ─────────────────────────────────────────────────────────────────

  Future<void> _onSosTap() async {
    HapticFeedback.vibrate();
    final TtsService tts = context.read<TtsService>();
    final SettingsProvider settings = context.read<SettingsProvider>();

    if (!settings.hasEmergencyContact) {
      await tts.speak('No emergency contact set. Please add one in Settings.');
      return;
    }

    await tts.speak('Sending emergency message.');
    final SosResult result =
        await SosService.sendEmergencySms(settings.emergencyContact);
    if (mounted) {
      await tts.speak(result.message);
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  String _friendlyCameraError(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
        return 'Camera permission denied. Please enable camera access in app settings.';
      case 'CameraAccessDeniedWithoutPrompt':
        return 'Camera permission was previously denied. Enable it from settings.';
      case 'CameraAccessRestricted':
        return 'Camera access is restricted on this device.';
      case 'AudioAccessDenied':
      case 'AudioAccessDeniedWithoutPrompt':
      case 'AudioAccessRestricted':
        return 'Microphone access issue detected. Please review app permissions.';
      default:
        return 'Camera initialization failed (${error.code}).';
    }
  }

  Future<void> _speakTextInChunks(TtsService tts, String text) async {
    final String normalized = text.replaceAll('\n', ' ').trim();
    if (normalized.isEmpty) return;

    const int chunkSize = 220;
    final List<String> chunks = <String>[];

    int start = 0;
    while (start < normalized.length) {
      int end = (start + chunkSize).clamp(0, normalized.length);
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

    for (final String chunk in chunks.where((c) => c.isNotEmpty)) {
      await tts.speak(chunk);
    }
  }

  bool get _powerReadMode => context.read<SettingsProvider>().powerReadMode;

  GeminiService _getGeminiService(String apiKey) {
    if (_geminiService == null || _geminiApiKey != apiKey) {
      _geminiService = GeminiService(apiKey: apiKey);
      _geminiApiKey = apiKey;
    }
    return _geminiService!;
  }

  void _triggerInitialActionIfNeeded() {
    if (_initialActionTriggered) return;
    if (widget.initialAction == CameraInitialAction.none) return;
    if (!_cameraService.isInitialized) return;

    _initialActionTriggered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isProcessing) return;
      switch (widget.initialAction) {
        case CameraInitialAction.read:
          unawaited(_onReadTap());
          break;
        case CameraInitialAction.identify:
          unawaited(_onIdentifyTap());
          break;
        case CameraInitialAction.describe:
          unawaited(_onDescribeTap());
          break;
        case CameraInitialAction.navigate:
          if (_isYoloReady) {
            _toggleNavigation();
          } else {
            _pendingInitialNavigateRetry = true;
          }
          break;
        case CameraInitialAction.none:
          break;
      }
    });
  }

  void _retryPendingInitialNavigate() {
    if (!_pendingInitialNavigateRetry) return;
    if (!_isYoloReady || !_cameraService.isInitialized || _isProcessing) return;
    if (!mounted || _isNavigating) return;

    _pendingInitialNavigateRetry = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isProcessing || _isNavigating) return;
      _toggleNavigation();
    });
  }

  Future<void> _serializeLifecycleShutdown() {
    final Future<void>? active = _lifecycleShutdownFuture;
    if (active != null) return active;

    final Future<void> shutdown = _performLifecycleShutdown();
    _lifecycleShutdownFuture = shutdown;
    return shutdown.whenComplete(() {
      if (identical(_lifecycleShutdownFuture, shutdown)) {
        _lifecycleShutdownFuture = null;
      }
    });
  }

  Future<void> _performLifecycleShutdown() async {
    if (_isNavigating) {
      await _stopNavigation(announce: false);
    } else {
      await _cameraService.stopImageStream();
    }
    await _cameraService.disposeController();
  }
}
