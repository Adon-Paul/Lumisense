class OcrResult {
  const OcrResult({
    required this.text,
    required this.lines,
    required this.processingTimeMs,
  });

  final String text;
  final List<String> lines;
  final int processingTimeMs;

  bool get hasText => text.trim().isNotEmpty;
}
