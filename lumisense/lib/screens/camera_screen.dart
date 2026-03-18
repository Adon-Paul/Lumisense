import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lumisense/services/camera_service.dart';
import 'package:lumisense/utils/theme.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();

  late Future<void> _cameraInitialization;
  String? _cameraError;
  bool _cameraPermissionPermanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cameraInitialization = _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final bool hasPermission = await _ensureCameraPermission();
    if (!hasPermission) {
      return;
    }

    try {
      await _cameraService.initialize();
      if (!mounted) {
        return;
      }
      setState(() {
        _cameraError = null;
        _cameraPermissionPermanentlyDenied = false;
      });
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _cameraError = _friendlyCameraError(error);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _cameraError = 'Unable to initialize the camera.';
      });
    }
  }

  Future<bool> _ensureCameraPermission() async {
    PermissionStatus status = await Permission.camera.status;
    if (status.isGranted) {
      return true;
    }

    status = await Permission.camera.request();
    if (status.isGranted) {
      return true;
    }

    if (!mounted) {
      return false;
    }

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
    final bool opened = await openAppSettings();
    if (!opened || !mounted) {
      return;
    }

    setState(() {
      _cameraInitialization = _initializeCamera();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _cameraService.disposeController();
      return;
    }

    if (state != AppLifecycleState.resumed) {
      return;
    }

    setState(() {
      _cameraInitialization = _initializeCamera();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.disposeController();
    super.dispose();
  }

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
              child: CircularProgressIndicator(
                color: AppTheme.primaryYellow,
              ),
            );
          }

          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  onTap: _onDescribeTap,
                  child: CameraPreview(_cameraService.controller!),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: <Widget>[
                        _buildTopButton(
                          icon: Icons.arrow_back,
                          label: 'Back',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Live Camera',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  minimum: const EdgeInsets.all(16),
                  child: _buildActionBar(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

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
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: Colors.white),
          ),
        ),
      ),
    );
  }

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
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildActionButton(
              icon: Icons.search,
              label: 'Identify',
              onPressed: _onIdentifyTap,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildActionButton(
              icon: Icons.auto_awesome,
              label: 'Describe',
              onPressed: _onDescribeTap,
              highlighted: true,
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
          onPressed: () {
            HapticFeedback.heavyImpact();
            onPressed();
          },
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: background,
            foregroundColor: foreground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 26),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.camera_alt_outlined,
              color: AppTheme.error,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.textPrimary,
                  ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _cameraError = null;
                  _cameraInitialization = _initializeCamera();
                });
              },
              child: const Text('Retry Camera'),
            ),
            if (_cameraPermissionPermanentlyDenied) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _openAppSettings,
                child: const Text('Open Settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _onReadTap() {
    _showActionToast('Read Text will run OCR in the next phase.');
  }

  void _onIdentifyTap() {
    _showActionToast('Identify will run object detection in the next phase.');
  }

  void _onDescribeTap() {
    _showActionToast('Describe will call Gemini scene analysis in the next phase.');
  }

  void _showActionToast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.primaryYellow,
          content: Text(
            message,
            style: const TextStyle(color: AppTheme.darkBackground),
          ),
        ),
      );
  }

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
}
