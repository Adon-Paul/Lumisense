import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import 'package:lumisense/models/upi_payment_info.dart';

/// Result of a QR code scan attempt.
class QrScanResult {
  const QrScanResult({
    required this.found,
    this.rawValue,
    this.upiInfo,
    this.processingTimeMs = 0,
  });

  /// Whether a QR code was detected.
  final bool found;

  /// Raw string value of the QR code.
  final String? rawValue;

  /// Parsed UPI payment info (null if QR is not a UPI code).
  final UpiPaymentInfo? upiInfo;

  /// How long the scan took in milliseconds.
  final int processingTimeMs;

  /// Whether this is a valid UPI payment QR.
  bool get isUpi => upiInfo != null;
}

/// Wraps ML Kit [BarcodeScanner] for QR code detection.
///
/// Follows the same pattern as [OcrService] — accepts an image path,
/// processes it, and returns a structured result.
class QrScannerService {
  QrScannerService()
      : _scanner = BarcodeScanner(formats: <BarcodeFormat>[BarcodeFormat.qrCode]);

  final BarcodeScanner _scanner;
  bool _isDisposed = false;

  /// Scans a single image for QR codes.
  ///
  /// Returns the first QR code found. If the QR contains a UPI URI,
  /// [QrScanResult.upiInfo] is populated.
  Future<QrScanResult> scanFromImagePath(String imagePath) async {
    if (_isDisposed) {
      throw StateError('QR scanner service has been disposed.');
    }

    final Stopwatch sw = Stopwatch()..start();

    final InputImage inputImage = InputImage.fromFilePath(imagePath);
    final List<Barcode> barcodes = await _scanner.processImage(inputImage);

    sw.stop();

    if (barcodes.isEmpty) {
      return QrScanResult(found: false, processingTimeMs: sw.elapsedMilliseconds);
    }

    // Take the first QR code found.
    final Barcode barcode = barcodes.first;
    final String? rawValue = barcode.rawValue;

    UpiPaymentInfo? upiInfo;
    if (rawValue != null && rawValue.isNotEmpty) {
      upiInfo = UpiPaymentInfo.fromUri(rawValue);
    }

    debugPrint('QrScannerService: found QR → $rawValue (UPI: ${upiInfo != null})');

    return QrScanResult(
      found: true,
      rawValue: rawValue,
      upiInfo: upiInfo,
      processingTimeMs: sw.elapsedMilliseconds,
    );
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _scanner.close();
  }
}
