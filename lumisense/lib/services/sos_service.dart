import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

/// Handles emergency SOS: obtains GPS location and sends an SMS with a
/// Google Maps link to the user's preset emergency contact.
///
/// Usage:
/// ```dart
/// final result = await SosService.sendEmergencySms('+91XXXXXXXXXX');
/// ```
class SosService {
  SosService._();

  /// Checks whether location services are enabled and permissions granted.
  /// If permission is undetermined, requests it. Returns `true` when ready.
  static Future<bool> ensureLocationPermission() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('SosService: location services disabled.');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('SosService: location permission denied ($permission).');
      return false;
    }

    return true;
  }

  /// Obtains the device's current GPS position.
  ///
  /// Falls back to last known position if the live fix times out.
  static Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('SosService: live position failed ($e), trying last known.');
      return Geolocator.getLastKnownPosition();
    }
  }

  /// Sends an emergency SMS with the user's GPS location to [phoneNumber].
  ///
  /// Returns a [SosResult] indicating success or failure with a user-friendly
  /// message suitable for TTS.
  static Future<SosResult> sendEmergencySms(String phoneNumber) async {
    if (phoneNumber.trim().isEmpty) {
      return const SosResult(
        success: false,
        message: 'No emergency contact set. Please add one in Settings.',
      );
    }

    // ── Location ──────────────────────────────────────────────────────────
    final bool hasPermission = await ensureLocationPermission();
    String locationText = 'Location unavailable.';

    if (hasPermission) {
      final Position? position = await getCurrentPosition();
      if (position != null) {
        final String mapsLink =
            'https://maps.google.com/?q=${position.latitude},${position.longitude}';
        locationText =
            'Lat: ${position.latitude.toStringAsFixed(6)}, '
            'Lng: ${position.longitude.toStringAsFixed(6)}\n$mapsLink';
      }
    }

    // ── SMS ───────────────────────────────────────────────────────────────
    final String body =
        'EMERGENCY from LumiSense!\n'
        'I need help. Here is my location:\n'
        '$locationText';

    final Uri smsUri = Uri(
      scheme: 'sms',
      path: phoneNumber.trim(),
      queryParameters: <String, String>{'body': body},
    );

    try {
      final bool launched = await launchUrl(
        smsUri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        return const SosResult(
          success: true,
          message: 'Emergency message opened. Please tap send to confirm.',
        );
      } else {
        return const SosResult(
          success: false,
          message: 'Could not open the SMS app. Please try calling for help.',
        );
      }
    } catch (e) {
      debugPrint('SosService: launchUrl failed: $e');
      return const SosResult(
        success: false,
        message: 'Failed to send emergency message. Please try again.',
      );
    }
  }
}

/// Result of an SOS attempt, with a [message] suitable for TTS output.
class SosResult {
  const SosResult({required this.success, required this.message});

  final bool success;
  final String message;
}
