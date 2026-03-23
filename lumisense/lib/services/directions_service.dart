import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:open_route_service/open_route_service.dart';

import 'package:lumisense/services/tts_service.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

/// A single step in a walking route.
class NavigationStep {
  const NavigationStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.type,
    required this.name,
    required this.waypointIndices,
  });

  /// Human-readable instruction (e.g., "Turn left onto Main Street").
  final String instruction;

  /// Distance in meters.
  final double distance;

  /// Duration in seconds.
  final double duration;

  /// Instruction type code (0=left, 1=right, 6=straight, 10=arrive, etc.).
  final int type;

  /// Street or road name.
  final String name;

  /// Indices into the route coordinate list.
  final List<double> waypointIndices;

  /// True if this is the arrival step.
  bool get isArrival => type == 10;

  /// True if this is the departure step.
  bool get isDeparture => type == 11;

  /// Formats distance as a human-friendly string.
  String get distanceText {
    if (distance < 10) return 'a few steps';
    if (distance < 100) return '${distance.round()} meters';
    if (distance < 1000) {
      final int rounded = (distance / 10).round() * 10;
      return '$rounded meters';
    }
    return '${(distance / 1000).toStringAsFixed(1)} kilometers';
  }

  /// Builds a TTS-friendly instruction with distance.
  String get spokenInstruction {
    if (isArrival) return 'You have arrived at your destination.';
    if (isDeparture) return '$instruction for $distanceText.';
    return 'In $distanceText, $instruction.';
  }
}

/// Result of a directions query.
class DirectionsResult {
  const DirectionsResult({
    required this.steps,
    required this.totalDistance,
    required this.totalDuration,
    required this.routeCoordinates,
  });

  /// Ordered list of navigation steps.
  final List<NavigationStep> steps;

  /// Total distance in meters.
  final double totalDistance;

  /// Total duration in seconds.
  final double totalDuration;

  /// Ordered coordinates forming the route polyline.
  final List<ORSCoordinate> routeCoordinates;

  /// Human-friendly total distance.
  String get totalDistanceText {
    if (totalDistance < 1000) return '${totalDistance.round()} meters';
    return '${(totalDistance / 1000).toStringAsFixed(1)} kilometers';
  }

  /// Human-friendly total duration.
  String get totalDurationText {
    final int minutes = (totalDuration / 60).round();
    if (minutes < 1) return 'less than a minute';
    if (minutes == 1) return '1 minute';
    if (minutes < 60) return '$minutes minutes';
    final int hours = minutes ~/ 60;
    final int remaining = minutes % 60;
    if (remaining == 0) return '$hours ${hours == 1 ? 'hour' : 'hours'}';
    return '$hours ${hours == 1 ? 'hour' : 'hours'} $remaining minutes';
  }
}

/// Result of a geocoding query.
class GeocodingResult {
  const GeocodingResult({
    required this.label,
    required this.coordinate,
  });

  /// Full address label.
  final String label;

  /// Coordinates of the place.
  final ORSCoordinate coordinate;
}

/// State of the active turn-by-turn navigation session.
enum NavSessionState { idle, fetchingRoute, navigating, rerouting, arrived }

// ─── Service ─────────────────────────────────────────────────────────────────

/// Manages turn-by-turn walking navigation using OpenRouteService.
///
/// Responsibilities:
/// - Geocoding destinations (text → coordinates)
/// - Fetching walking directions
/// - Tracking GPS position and advancing through route steps
/// - Announcing upcoming turns via [TtsService]
/// - Detecting off-route and triggering re-route
///
/// Usage:
/// ```dart
/// final nav = DirectionsService(apiKey: 'FREE_ORS_KEY', tts: ttsService);
/// await nav.startNavigation(destinationQuery: 'Central Park');
/// // GPS tracking starts automatically...
/// nav.stopNavigation();
/// ```
class DirectionsService extends ChangeNotifier {
  DirectionsService({
    required String apiKey,
    required TtsService tts,
  })  : _tts = tts,
        _ors = OpenRouteService(apiKey: apiKey);

  final TtsService _tts;
  final OpenRouteService _ors;

  // ─── State ────────────────────────────────────────────────────────────────

  NavSessionState _state = NavSessionState.idle;
  NavSessionState get state => _state;

  DirectionsResult? _route;
  DirectionsResult? get route => _route;

  int _currentStepIndex = 0;
  int get currentStepIndex => _currentStepIndex;

  NavigationStep? get currentStep =>
      _route != null && _currentStepIndex < _route!.steps.length
          ? _route!.steps[_currentStepIndex]
          : null;

  NavigationStep? get nextStep =>
      _route != null && _currentStepIndex + 1 < _route!.steps.length
          ? _route!.steps[_currentStepIndex + 1]
          : null;

  Position? _lastPosition;
  Position? get lastPosition => _lastPosition;

  String? _destinationLabel;
  String? get destinationLabel => _destinationLabel;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  StreamSubscription<Position>? _positionSub;

  /// Distance in meters at which we consider the user has reached a waypoint.
  static const double _waypointReachedThreshold = 20.0;

  /// Distance in meters before a turn where we give an early warning.
  static const double _earlyWarningDistance = 50.0;

  /// Distance in meters from route line to trigger re-routing.
  static const double _offRouteThreshold = 40.0;

  /// Minimum time between step announcements.
  static const Duration _announceCooldown = Duration(seconds: 4);

  /// Minimum time between re-route attempts.
  static const Duration _rerouteCooldown = Duration(seconds: 15);

  DateTime _lastAnnounceTime = DateTime(2000);
  DateTime _lastRerouteTime = DateTime(2000);
  bool _earlyWarningGiven = false;
  bool _isRerouting = false;

  bool get isNavigating => _state == NavSessionState.navigating;
  bool get isActive => _state != NavSessionState.idle;

  // ─── Geocoding ────────────────────────────────────────────────────────────

  /// Geocodes a text query to a list of matching places.
  Future<List<GeocodingResult>> geocode(String query, {
    ORSCoordinate? focusPoint,
  }) async {
    try {
      final GeoJsonFeatureCollection result = await _ors.geocodeSearchGet(
        text: query,
        focusPointCoordinate: focusPoint,
        size: 5,
      );

      return result.features.map((GeoJsonFeature f) {
        final String label =
            (f.properties['label'] as String?) ?? query;

        // Coordinates come as [longitude, latitude] in GeoJSON.
        ORSCoordinate coord;
        if (f.geometry.coordinates.isNotEmpty &&
            f.geometry.coordinates.first.isNotEmpty) {
          coord = f.geometry.coordinates.first.first;
        } else {
          // Fallback: try to extract from bbox.
          coord = f.bbox?.first ?? ORSCoordinate(latitude: 0, longitude: 0);
        }

        return GeocodingResult(label: label, coordinate: coord);
      }).toList();
    } catch (e) {
      debugPrint('DirectionsService geocode error: $e');
      return <GeocodingResult>[];
    }
  }

  // ─── Directions ───────────────────────────────────────────────────────────

  /// Fetches walking directions between two coordinates.
  Future<DirectionsResult?> getWalkingDirections({
    required ORSCoordinate start,
    required ORSCoordinate end,
  }) async {
    try {
      final List<DirectionRouteData> routes =
          await _ors.directionsMultiRouteDataPost(
        coordinates: <ORSCoordinate>[start, end],
        profileOverride: ORSProfile.footWalking,
        instructions: true,
        instructionsFormat: 'text',
        language: 'en',
        units: 'm',
      );

      if (routes.isEmpty) return null;
      final DirectionRouteData routeData = routes.first;

      // Parse steps from segments.
      final List<NavigationStep> steps = <NavigationStep>[];
      for (final DirectionRouteSegment segment in routeData.segments) {
        for (final DirectionRouteSegmentStep step in segment.steps) {
          steps.add(NavigationStep(
            instruction: step.instruction,
            distance: step.distance,
            duration: step.duration,
            type: step.type,
            name: step.name,
            waypointIndices: step.wayPoints,
          ));
        }
      }

      // Parse route polyline coordinates.
      List<ORSCoordinate> routeCoords = <ORSCoordinate>[];
      // Route data may contain the geometry as encoded polyline;
      // the wayPoints field in steps references indices in the coordinate list.
      // We need to get coordinates from the GeoJSON response.
      try {
        final GeoJsonFeatureCollection geoJson =
            await _ors.directionsMultiRouteGeoJsonPost(
          coordinates: <ORSCoordinate>[start, end],
          profileOverride: ORSProfile.footWalking,
          instructions: false,
          units: 'm',
        );
        if (geoJson.features.isNotEmpty) {
          final GeoJsonFeatureGeometry geo = geoJson.features.first.geometry;
          if (geo.coordinates.isNotEmpty) {
            routeCoords = geo.coordinates.first;
          }
        }
      } catch (e) {
        debugPrint('DirectionsService: failed to get route coordinates: $e');
        // Fall back to just start/end.
        routeCoords = <ORSCoordinate>[start, end];
      }

      return DirectionsResult(
        steps: steps,
        totalDistance: routeData.summary.distance,
        totalDuration: routeData.summary.duration,
        routeCoordinates: routeCoords,
      );
    } catch (e) {
      debugPrint('DirectionsService directions error: $e');
      rethrow;
    }
  }

  // ─── Navigation session ───────────────────────────────────────────────────

  /// Starts a turn-by-turn walking navigation session.
  ///
  /// [destinationQuery] is geocoded, or use [destinationCoord] directly.
  Future<bool> startNavigation({
    String? destinationQuery,
    ORSCoordinate? destinationCoord,
    String? destinationName,
  }) async {
    if (_state != NavSessionState.idle) {
      stopNavigation();
    }

    _state = NavSessionState.fetchingRoute;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Get current position.
      await _tts.speak('Getting your location.');
      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _lastPosition = pos;

      final ORSCoordinate startCoord = ORSCoordinate(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );

      // 2. Resolve destination.
      ORSCoordinate endCoord;
      if (destinationCoord != null) {
        endCoord = destinationCoord;
        _destinationLabel = destinationName ?? 'destination';
      } else if (destinationQuery != null && destinationQuery.isNotEmpty) {
        await _tts.speak('Searching for $destinationQuery.');
        final List<GeocodingResult> results = await geocode(
          destinationQuery,
          focusPoint: startCoord,
        );
        if (results.isEmpty) {
          _errorMessage = 'Could not find "$destinationQuery". Please try a different name.';
          _state = NavSessionState.idle;
          notifyListeners();
          await _tts.speak(_errorMessage!);
          return false;
        }
        endCoord = results.first.coordinate;
        _destinationLabel = results.first.label;
      } else {
        _errorMessage = 'No destination specified.';
        _state = NavSessionState.idle;
        notifyListeners();
        return false;
      }

      // 3. Fetch walking directions.
      await _tts.speak('Calculating walking route.');
      final DirectionsResult? result = await getWalkingDirections(
        start: startCoord,
        end: endCoord,
      );

      if (result == null || result.steps.isEmpty) {
        _errorMessage = 'No walking route found to $_destinationLabel.';
        _state = NavSessionState.idle;
        notifyListeners();
        await _tts.speak(_errorMessage!);
        return false;
      }

      _route = result;
      _currentStepIndex = 0;
      _earlyWarningGiven = false;
      _state = NavSessionState.navigating;
      notifyListeners();

      // 4. Announce route summary.
      final String summary =
          'Route to $_destinationLabel. '
          '${result.totalDistanceText}, about ${result.totalDurationText} walking. '
          '${result.steps.length} steps. ';

      final String firstInstruction = result.steps.first.spokenInstruction;
      await _tts.speakAndWait('$summary $firstInstruction');

      // 5. Start GPS tracking.
      _startGpsTracking();

      return true;
    } catch (e) {
      debugPrint('DirectionsService startNavigation error: $e');
      _errorMessage = 'Unable to start navigation. Please check your connection.';
      _state = NavSessionState.idle;
      notifyListeners();
      await _tts.speak(_errorMessage!);
      return false;
    }
  }

  /// Stops the current navigation session.
  void stopNavigation() {
    _positionSub?.cancel();
    _positionSub = null;
    _route = null;
    _currentStepIndex = 0;
    _destinationLabel = null;
    _errorMessage = null;
    _earlyWarningGiven = false;
    _state = NavSessionState.idle;
    notifyListeners();
  }

  /// Repeats the current navigation instruction.
  Future<void> repeatCurrentStep() async {
    if (!isNavigating || currentStep == null) return;
    await _tts.speak(currentStep!.spokenInstruction);
  }

  /// Announces a brief status summary (distance remaining, current step).
  Future<void> announceStatus() async {
    if (!isNavigating || _route == null) return;

    // Calculate remaining distance from current step onward.
    double remaining = 0;
    for (int i = _currentStepIndex; i < _route!.steps.length; i++) {
      remaining += _route!.steps[i].distance;
    }

    final String distText = remaining < 1000
        ? '${remaining.round()} meters'
        : '${(remaining / 1000).toStringAsFixed(1)} kilometers';

    final int stepsLeft = _route!.steps.length - _currentStepIndex;
    await _tts.speak(
      '$distText remaining, $stepsLeft steps to go. '
      '${currentStep?.spokenInstruction ?? ""}',
    );
  }

  // ─── GPS tracking ────────────────────────────────────────────────────────

  void _startGpsTracking() {
    _positionSub?.cancel();

    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // update every 5 meters
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPositionUpdate, onError: (dynamic e) {
      debugPrint('DirectionsService GPS error: $e');
    });
  }

  void _onPositionUpdate(Position position) {
    _lastPosition = position;

    if (_state != NavSessionState.navigating || _route == null) return;

    final NavigationStep? step = currentStep;
    if (step == null) return;

    // Calculate distance to the next waypoint (the end of the current step).
    final double distToNext = _distanceToNextWaypoint(position);

    // Check if we've reached the next waypoint.
    if (distToNext < _waypointReachedThreshold) {
      _advanceStep();
      return;
    }

    // Early warning when approaching a turn.
    if (!_earlyWarningGiven &&
        distToNext < _earlyWarningDistance &&
        !step.isDeparture &&
        nextStep != null) {
      _earlyWarningGiven = true;
      _announceIfCooldownPassed(
        'In ${distToNext.round()} meters, ${nextStep!.instruction}.',
      );
      return;
    }

    // Check if off-route.
    final double distFromRoute = _distanceFromRouteLine(position);
    if (distFromRoute > _offRouteThreshold) {
      _handleOffRoute(position);
    }

    notifyListeners();
  }

  void _advanceStep() {
    _currentStepIndex++;
    _earlyWarningGiven = false;
    HapticFeedback.mediumImpact();

    if (_currentStepIndex >= (_route?.steps.length ?? 0)) {
      // Arrived!
      HapticFeedback.heavyImpact();
      _state = NavSessionState.arrived;
      _positionSub?.cancel();
      _positionSub = null;
      notifyListeners();
      unawaited(_tts.speakUrgent(
        'You have arrived at $_destinationLabel. Navigation complete.',
      ));
      return;
    }

    notifyListeners();

    final NavigationStep step = _route!.steps[_currentStepIndex];
    _announceIfCooldownPassed(step.spokenInstruction);
  }

  Future<void> _handleOffRoute(Position position) async {
    if (_isRerouting) return; // prevent concurrent reroutes
    final DateTime now = DateTime.now();
    if (now.difference(_lastRerouteTime) < _rerouteCooldown) return;
    _lastRerouteTime = now;
    _isRerouting = true;

    debugPrint('DirectionsService: Off route, attempting re-route...');
    _state = NavSessionState.rerouting;
    notifyListeners();

    await _tts.speak('You seem to be off route. Recalculating.');

    // Find the original destination from the last step.
    if (_route == null || _route!.routeCoordinates.isEmpty) {
      _state = NavSessionState.navigating;
      notifyListeners();
      return;
    }

    final ORSCoordinate destination = _route!.routeCoordinates.last;
    final ORSCoordinate currentPos = ORSCoordinate(
      latitude: position.latitude,
      longitude: position.longitude,
    );

    try {
      final DirectionsResult? newRoute = await getWalkingDirections(
        start: currentPos,
        end: destination,
      );

      if (newRoute != null && newRoute.steps.isNotEmpty) {
        _route = newRoute;
        _currentStepIndex = 0;
        _earlyWarningGiven = false;
        _state = NavSessionState.navigating;
        notifyListeners();

        await _tts.speak(
          'Route recalculated. ${newRoute.totalDistanceText} remaining. '
          '${newRoute.steps.first.spokenInstruction}',
        );
      } else {
        _state = NavSessionState.navigating;
        notifyListeners();
        await _tts.speak('Could not recalculate route. Continuing with current directions.');
      }
    } catch (e) {
      debugPrint('Re-route failed: $e');
      _state = NavSessionState.navigating;
      notifyListeners();
    } finally {
      _isRerouting = false;
    }
  }

  // ─── Distance calculations ────────────────────────────────────────────────

  /// Calculates distance from user's position to the next waypoint.
  double _distanceToNextWaypoint(Position position) {
    if (_route == null || _route!.routeCoordinates.isEmpty) return double.infinity;

    // Get the waypoint index for the END of the current step.
    final NavigationStep? step = currentStep;
    if (step == null) return double.infinity;

    int targetIdx;
    if (step.waypointIndices.length >= 2) {
      targetIdx = step.waypointIndices.last.round();
    } else if (_currentStepIndex + 1 < _route!.steps.length) {
      // Use the first waypoint of the next step.
      final NavigationStep next = _route!.steps[_currentStepIndex + 1];
      targetIdx = next.waypointIndices.isNotEmpty
          ? next.waypointIndices.first.round()
          : 0;
    } else {
      // Last step — target is the last coordinate.
      targetIdx = _route!.routeCoordinates.length - 1;
    }

    targetIdx = targetIdx.clamp(0, _route!.routeCoordinates.length - 1);
    final ORSCoordinate target = _route!.routeCoordinates[targetIdx];

    return _haversineMeters(
      position.latitude, position.longitude,
      target.latitude, target.longitude,
    );
  }

  /// Calculates the minimum distance from the user to the route polyline.
  double _distanceFromRouteLine(Position position) {
    if (_route == null || _route!.routeCoordinates.length < 2) {
      return 0;
    }

    double minDist = double.infinity;
    // Only check nearby segments to save CPU (current step ± 5).
    final int startIdx = (_currentStepIndex > 0 ? _currentStepIndex - 1 : 0)
        .clamp(0, _route!.routeCoordinates.length - 2);
    final int endIdx = (_currentStepIndex + 10)
        .clamp(0, _route!.routeCoordinates.length - 1);

    for (int i = startIdx; i < endIdx; i++) {
      final ORSCoordinate a = _route!.routeCoordinates[i];
      final ORSCoordinate b = _route!.routeCoordinates[i + 1];
      final double d = _pointToSegmentDistance(
        position.latitude, position.longitude,
        a.latitude, a.longitude,
        b.latitude, b.longitude,
      );
      if (d < minDist) minDist = d;
    }

    return minDist;
  }

  /// Haversine distance in meters between two lat/lng points.
  static double _haversineMeters(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const double R = 6371000; // Earth radius in meters
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  /// Approximate distance from a point to a line segment (in meters).
  static double _pointToSegmentDistance(
    double pLat, double pLon,
    double aLat, double aLon,
    double bLat, double bLon,
  ) {
    // Project point onto segment using dot product in lat/lon space.
    final double dx = bLon - aLon;
    final double dy = bLat - aLat;
    if (dx == 0 && dy == 0) {
      return _haversineMeters(pLat, pLon, aLat, aLon);
    }
    double t = ((pLon - aLon) * dx + (pLat - aLat) * dy) / (dx * dx + dy * dy);
    t = t.clamp(0.0, 1.0);
    final double closestLon = aLon + t * dx;
    final double closestLat = aLat + t * dy;
    return _haversineMeters(pLat, pLon, closestLat, closestLon);
  }

  // ─── TTS helpers ──────────────────────────────────────────────────────────

  void _announceIfCooldownPassed(String text) {
    final DateTime now = DateTime.now();
    if (now.difference(_lastAnnounceTime) < _announceCooldown) return;
    _lastAnnounceTime = now;
    unawaited(_tts.speak(text));
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }
}
