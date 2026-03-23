/// Parsed UPI payment information from a QR code.
///
/// UPI QR codes follow the format:
/// `upi://pay?pa=<VPA>&pn=<PayeeName>&am=<Amount>&cu=INR&tn=<Note>`
class UpiPaymentInfo {
  const UpiPaymentInfo({
    required this.vpa,
    this.payeeName,
    this.amount,
    this.currency,
    this.transactionNote,
    this.rawUri,
  });

  /// Virtual Payment Address (e.g. "shop@upi", "9876543210@ybl").
  final String vpa;

  /// Display name of the payee.
  final String? payeeName;

  /// Amount to pay (may be null if QR doesn't specify).
  final double? amount;

  /// Currency code (typically "INR").
  final String? currency;

  /// Transaction note / description.
  final String? transactionNote;

  /// The original raw URI string from the QR code.
  final String? rawUri;

  /// Parses a raw UPI URI string into [UpiPaymentInfo].
  ///
  /// Returns `null` if the string is not a valid UPI payment URI.
  static UpiPaymentInfo? fromUri(String raw) {
    final String trimmed = raw.trim();
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    // Must be upi:// scheme with "pay" host/path
    if (uri.scheme.toLowerCase() != 'upi') return null;

    final Map<String, String> params = uri.queryParameters;
    final String? vpa = params['pa'];
    if (vpa == null || vpa.isEmpty) return null;

    double? amount;
    final String? amStr = params['am'];
    if (amStr != null && amStr.isNotEmpty) {
      amount = double.tryParse(amStr);
    }

    return UpiPaymentInfo(
      vpa: vpa,
      payeeName: params['pn'],
      amount: amount,
      currency: params['cu'] ?? 'INR',
      transactionNote: params['tn'],
      rawUri: trimmed,
    );
  }

  /// Builds a UPI intent URI for launching a payment app.
  ///
  /// Uses the parsed fields; [overrideAmount] replaces the QR amount if set.
  String toUpiUri({double? overrideAmount}) {
    final Map<String, String> params = <String, String>{
      'pa': vpa,
    };
    if (payeeName != null) params['pn'] = payeeName!;

    final double? amt = overrideAmount ?? amount;
    if (amt != null) params['am'] = amt.toStringAsFixed(2);

    params['cu'] = currency ?? 'INR';
    if (transactionNote != null) params['tn'] = transactionNote!;

    final Uri uri = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: params,
    );
    return uri.toString();
  }

  /// Human-readable summary for TTS announcement.
  String get spokenSummary {
    final StringBuffer sb = StringBuffer();
    sb.write('Payment to ');
    sb.write(payeeName ?? vpa);
    if (amount != null) {
      sb.write(', amount ${amount!.toStringAsFixed(2)} ${currency ?? "rupees"}');
    } else {
      sb.write(', amount not specified');
    }
    return sb.toString();
  }

  @override
  String toString() =>
      'UpiPaymentInfo(vpa: $vpa, payee: $payeeName, amount: $amount)';
}
