import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:open_route_service/open_route_service.dart';

import 'package:lumisense/services/directions_service.dart';
import 'package:lumisense/services/tts_service.dart';
import 'package:lumisense/utils/theme.dart';

/// Full-screen map view showing the active walking route.
///
/// Displays:
/// - Route polyline (electric blue)
/// - Start marker (green)
/// - Destination marker (red)
/// - User location (pulsing blue dot)
/// - Current step info panel at bottom
class RouteMapScreen extends StatefulWidget {
  const RouteMapScreen({
    super.key,
    required this.directionsService,
    required this.tts,
  });

  final DirectionsService directionsService;
  final TtsService tts;

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  final MapController _mapController = MapController();

  DirectionsService get _ds => widget.directionsService;

  @override
  void initState() {
    super.initState();
    _ds.addListener(_onUpdate);
    widget.tts.speak('Map view. Showing your walking route.');
  }

  @override
  void dispose() {
    _ds.removeListener(_onUpdate);
    _mapController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  List<LatLng> get _routePoints {
    final List<ORSCoordinate>? coords = _ds.route?.routeCoordinates;
    if (coords == null || coords.isEmpty) return <LatLng>[];
    return coords
        .map((ORSCoordinate c) => LatLng(c.latitude, c.longitude))
        .toList();
  }

  LatLng? get _userLatLng {
    final pos = _ds.lastPosition;
    if (pos == null) return null;
    return LatLng(pos.latitude, pos.longitude);
  }

  void _centerOnUser() {
    HapticFeedback.lightImpact();
    final LatLng? user = _userLatLng;
    if (user != null) {
      _mapController.move(user, 17);
      widget.tts.speak('Centered on your location.');
    }
  }

  void _fitRoute() {
    HapticFeedback.lightImpact();
    final List<LatLng> points = _routePoints;
    if (points.length >= 2) {
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.all(60),
        ),
      );
      widget.tts.speak('Showing full route.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<LatLng> points = _routePoints;
    final LatLng? userPos = _userLatLng;
    final NavigationStep? step = _ds.currentStep;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: Stack(
        children: <Widget>[
          // ── Map ──────────────────────────────────────────────────────────
          Positioned.fill(
            child: points.isEmpty
                ? const Center(
                    child: Text(
                      'No route loaded',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                    ),
                  )
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCameraFit: CameraFit.coordinates(
                        coordinates: points,
                        padding: const EdgeInsets.all(60),
                      ),
                    ),
                    children: <Widget>[
                      // Tile layer (OpenStreetMap)
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        maxZoom: 19,
                        userAgentPackageName: 'com.lumisense.app',
                      ),

                      // Route polyline
                      PolylineLayer(
                        polylines: <Polyline>[
                          Polyline(
                            points: points,
                            color: AppTheme.accentBlue,
                            strokeWidth: 5.0,
                          ),
                        ],
                      ),

                      // Markers
                      MarkerLayer(
                        markers: <Marker>[
                          // Start (green circle)
                          Marker(
                            point: points.first,
                            width: 36,
                            height: 36,
                            child: const _MapMarker(
                              icon: Icons.trip_origin,
                              color: AppTheme.success,
                              size: 28,
                            ),
                          ),

                          // Destination (red pin)
                          Marker(
                            point: points.last,
                            width: 40,
                            height: 40,
                            child: const _MapMarker(
                              icon: Icons.location_on,
                              color: AppTheme.error,
                              size: 36,
                            ),
                          ),

                          // User location (blue pulsing dot)
                          if (userPos != null)
                            Marker(
                              point: userPos,
                              width: 32,
                              height: 32,
                              child: const _UserLocationDot(),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),

          // ── Top bar ──────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: <Widget>[
                    // Back button
                    _MapButton(
                      icon: Icons.arrow_back,
                      label: 'Back to camera',
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        Navigator.of(context).pop();
                      },
                    ),
                    const Spacer(),
                    // Destination label
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _ds.destinationLabel ?? 'Route Map',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48), // balance the back button
                  ],
                ),
              ),
            ),
          ),

          // ── Floating action buttons (right side) ─────────────────────────
          Positioned(
            right: 16,
            bottom: (step != null ? 160 : 100),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _MapButton(
                  icon: Icons.my_location,
                  label: 'Center on me',
                  onPressed: _centerOnUser,
                ),
                const SizedBox(height: 12),
                _MapButton(
                  icon: Icons.fit_screen,
                  label: 'Fit route',
                  onPressed: _fitRoute,
                ),
              ],
            ),
          ),

          // ── Bottom step panel ────────────────────────────────────────────
          if (step != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Semantics(
                    label: 'Current step: ${step.instruction}. Tap to hear again.',
                    button: true,
                    child: Material(
                      color: AppTheme.cardBackground.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _ds.repeatCurrentStep();
                        },
                        borderRadius: BorderRadius.circular(20),
                        splashColor: AppTheme.accentBlue.withValues(alpha: 0.15),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.accentBlue.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Icon(
                                    _stepIcon(step.type),
                                    color: AppTheme.accentBlue,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Step ${_ds.currentStepIndex + 1} of ${_ds.route?.steps.length ?? 0}',
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accentBlue
                                          .withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      step.distanceText,
                                      style: const TextStyle(
                                        color: AppTheme.accentBlue,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                step.instruction,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tap to hear again',
                                style: TextStyle(
                                  color: AppTheme.textHint.withValues(alpha: 0.7),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _stepIcon(int type) {
    switch (type) {
      case 0: return Icons.turn_left;
      case 1: return Icons.turn_right;
      case 2: return Icons.turn_sharp_left;
      case 3: return Icons.turn_sharp_right;
      case 4: return Icons.turn_slight_left;
      case 5: return Icons.turn_slight_right;
      case 6: return Icons.straight;
      case 10: return Icons.flag;
      case 11: return Icons.my_location;
      case 12: return Icons.turn_slight_left;
      case 13: return Icons.turn_slight_right;
      default: return Icons.directions_walk;
    }
  }
}

// ─── Map helper widgets ──────────────────────────────────────────────────────

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: Material(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onPressed();
          },
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({
    required this.icon,
    required this.color,
    required this.size,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, color: color, size: size);
  }
}

class _UserLocationDot extends StatefulWidget {
  const _UserLocationDot();

  @override
  State<_UserLocationDot> createState() => _UserLocationDotState();
}

class _UserLocationDotState extends State<_UserLocationDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (BuildContext context, Widget? child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.accentBlue.withValues(alpha: _animation.value),
            border: Border.all(color: AppTheme.accentBlue, width: 2.5),
          ),
          child: const Center(
            child: Icon(
              Icons.navigation,
              color: Colors.white,
              size: 14,
            ),
          ),
        );
      },
    );
  }
}
