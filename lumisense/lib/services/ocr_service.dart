import 'dart:math';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:lumisense/models/ocr_result.dart';

class OcrService {
  OcrService() : _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _textRecognizer;
  bool _isDisposed = false;

  Future<OcrResult> extractTextFromImagePath(String imagePath) async {
    if (_isDisposed) {
      throw StateError('OCR service has been disposed.');
    }

    final Stopwatch stopwatch = Stopwatch()..start();

    final InputImage inputImage = InputImage.fromFilePath(imagePath);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

    final List<_LineChunk> chunks = <_LineChunk>[];

    for (final TextBlock block in recognizedText.blocks) {
      for (final TextLine line in block.lines) {
        final String trimmed = line.text.trim();
        if (trimmed.isEmpty) {
          continue;
        }

        final rect = line.boundingBox;
        chunks.add(
          _LineChunk(
            text: trimmed,
            top: rect.top,
            left: rect.left,
          ),
        );
      }
    }

    chunks.sort((a, b) {
      final double verticalDiff = (a.top - b.top).abs();
      if (verticalDiff > 6) {
        return a.top.compareTo(b.top);
      }
      return a.left.compareTo(b.left);
    });

    final List<String> lines = chunks.map((c) => c.text).toList(growable: false);
    final String text = lines.join('\n');

    stopwatch.stop();

    return OcrResult(
      text: text,
      lines: lines,
      processingTimeMs: max(0, stopwatch.elapsedMilliseconds),
    );
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _textRecognizer.close();
  }
}

class _LineChunk {
  const _LineChunk({
    required this.text,
    required this.top,
    required this.left,
  });

  final String text;
  final double top;
  final double left;
}
