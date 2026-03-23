import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Handles emergency SOS: obtains GPS location and sends an SMS with a
/// Google Maps link to the user's preset emergency contact.
///
/// Features:
/// - Auto-retry on SMS launch failure (up to 3 attempts)
/// - Fallback to direct phone call if SMS fails entirely
/// - Includes timestamp and Google Maps link in the message
///
/// Usage:
/// ```dart
/// final result = await SosService.sendEmergencySms('+91XXXXXXXXXX');
/// ```
class SosService {
  SosService._();

  /// Maximum number of SMS send attempts before falling back to a phone call.
  static const int _maxRetries = 3;

  // ─── Location ──────────────────────────────────────────────────────────────

  /// Checks whether location services are enabled and permissions granted.
  /// If permission is undetermined, requests it. Returns `true` when ready.
  static Future<bool> ensureLocationPermission() async {
    try {
      final bool serviceEnabled =
          await Geolocator.isLocationServiceEnabled();
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
    } catch (e) {
      debugPrint('SosService: ensureLocationPermission failed: $e');
      return false;
    }
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
      debugPrint(
          'SosService: live position failed ($e), trying last known.');
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  // ─── SMS + SOS ─────────────────────────────────────────────────────────────

  /// Sends an emergency SMS with the user's GPS location to [phoneNumber].
  ///
  /// Retry logic:
  /// 1. Attempts SMS launch up to [_maxRetries] times.
  /// 2. If all SMS attempts fail, falls back to a direct phone call.
  ///
  /// Returns a [SosResult] indicating success or failure with a user-friendly
  /// message suitable for TTS.
  static Future<SosResult> sendEmergencySms(String phoneNumber) async {
    // ── Validate ──────────────────────────────────────────────────────────
    final String normalized =
        phoneNumber.replaceAll(RegExp(r'[\s\-().]'), '').trim();

    if (normalized.isEmpty) {
      return const SosResult(
        success: false,
        message: 'No emergency contact set. Please add one in Settings.',
      );
    }

    if (normalized.replaceAll(RegExp(r'[^\d]'), '').length < 7) {
      return const SosResult(
        success: false,
        message: 'Emergency contact number appears invalid. '
            'Please check it in Settings.',
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

    // ── Build SMS body ────────────────────────────────────────────────────
    final String timestamp =
        DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

    final String body =
        'EMERGENCY from LumiSense!\n'
        'Time: $timestamp\n'
        'I need help. Here is my location:\n'
        '$locationText';

    final Uri smsUri = Uri(
      scheme: 'sms',
      path: normalized,
      queryParameters: <String, String>{'body': body},
    );

    // ── Attempt SMS with retries ──────────────────────────────────────────
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        final bool launched = await launchUrl(
          smsUri,
          mode: LaunchMode.externalApplication,
        );

        if (launched) {
          return const SosResult(
            success: true,
            message:
                'Emergency message opened. Please tap send to confirm.',
          );
        }

        // Wait briefly before retrying.
        if (attempt < _maxRetries) {
          await Future<void>.delayed(Duration(seconds: attempt));
        }
      } catch (e) {
        debugPrint('SosService: SMS attempt $attempt failed: $e');
        if (attempt < _maxRetries) {
          await Future<void>.delayed(Duration(seconds: attempt));
        }
      }
    }

    // ── Fallback: phone call ──────────────────────────────────────────────
    return _fallbackPhoneCall(normalized);
  }

  /// Attempts to directly call the emergency contact as a last resort.
  static Future<SosResult> _fallbackPhoneCall(String phoneNumber) async {
    try {
      final Uri telUri = Uri(scheme: 'tel', path: phoneNumber);
      final bool launched = await launchUrl(
        telUri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        return const SosResult(
          success: true,
          message: 'SMS could not be sent. Calling your emergency contact instead.',
        );
      }
    } catch (e) {
      debugPrint('SosService: phone call fallback failed: $e');
    }

    return const SosResult(
      success: false,
      message:
          'Could not send message or call. Please ask someone nearby for help.',
    );
  }
}

/// Result of an SOS attempt, with a [message] suitable for TTS output.
class SosResult {
  const SosResult({required this.success, required this.message});

  final bool success;
  final String message;
}
