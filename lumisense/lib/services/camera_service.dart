import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

/// Manages camera discovery, controller lifecycle, and capture operations.
class CameraService {
  CameraService._internal();

  static final CameraService _instance = CameraService._internal();

  factory CameraService() => _instance;

  final List<CameraDescription> _availableCameras = <CameraDescription>[];

  CameraController? _controller;
  CameraDescription? _activeCamera;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  Future<void> initialize({
    CameraLensDirection preferredLensDirection = CameraLensDirection.back,
  }) async {
    if (_controller != null && _controller!.value.isInitialized) {
      return;
    }

    if (_availableCameras.isEmpty) {
      final List<CameraDescription> discovered = await availableCameras();
      _availableCameras.addAll(discovered);
    }

    if (_availableCameras.isEmpty) {
      throw CameraException(
        'NoCameraFound',
        'No cameras were found on this device.',
      );
    }

    final CameraDescription selectedCamera = _selectCamera(preferredLensDirection);
    _activeCamera = selectedCamera;

    final CameraController nextController = CameraController(
      selectedCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await nextController.initialize();
      await nextController.setFlashMode(FlashMode.off);
    } on CameraException {
      await nextController.dispose();
      rethrow;
    }

    _controller = nextController;
  }

  Future<void> reinitialize() async {
    await disposeController();
    await initialize();
  }

  Future<XFile> captureStillImage() async {
    final CameraController? activeController = _controller;
    if (activeController == null || !activeController.value.isInitialized) {
      throw CameraException('UninitializedCamera', 'Camera is not initialized.');
    }

    if (activeController.value.isTakingPicture) {
      throw CameraException('CaptureInProgress', 'A capture is already in progress.');
    }

    return activeController.takePicture();
  }

  Future<void> disposeController() async {
    final CameraController? activeController = _controller;
    _controller = null;

    if (activeController != null) {
      await activeController.dispose();
    }
  }

  CameraDescription _selectCamera(CameraLensDirection preferredLensDirection) {
    return _availableCameras.firstWhere(
      (CameraDescription camera) => camera.lensDirection == preferredLensDirection,
      orElse: () => _availableCameras.first,
    );
  }

  Future<void> handleLifecycleState(AppLifecycleState state) async {
    final CameraController? activeController = _controller;

    if (activeController == null || !activeController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      await disposeController();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      await initialize(
        preferredLensDirection:
            _activeCamera?.lensDirection ?? CameraLensDirection.back,
      );
    }
  }
}
