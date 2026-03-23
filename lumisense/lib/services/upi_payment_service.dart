import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:lumisense/models/upi_payment_info.dart';

/// Handles launching UPI payment intents from parsed QR data.
class UpiPaymentService {
  const UpiPaymentService();

  /// Launches the system UPI app chooser (GPay, PhonePe, Paytm, etc.)
  /// with the payment details from [info].
  ///
  /// Returns `true` if the intent was launched successfully.
  Future<bool> launchPayment(UpiPaymentInfo info) async {
    final String uriString = info.toUpiUri();
    final Uri uri = Uri.parse(uriString);

    debugPrint('UpiPaymentService: launching $uriString');

    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        debugPrint('UpiPaymentService: launchUrl returned false');
      }
      return launched;
    } catch (e) {
      debugPrint('UpiPaymentService: launch failed: $e');
      return false;
    }
  }

  /// Checks whether any UPI app is available on the device.
  Future<bool> canLaunchUpi() async {
    try {
      return await canLaunchUrl(Uri.parse('upi://pay?pa=test@upi'));
    } catch (_) {
      return false;
    }
  }
}
