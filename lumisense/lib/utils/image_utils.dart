import 'dart:io';
import 'dart:typed_data';

/// Utility functions for image preprocessing before AI inference.
class ImageUtils {
  ImageUtils._();

  /// Reads a JPEG file and returns its raw bytes.
  ///
  /// Throws [FileSystemException] if the file does not exist.
  static Future<Uint8List> readJpegBytes(String filePath) async {
    final File file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Image file not found.', filePath);
    }
    return file.readAsBytes();
  }

  /// Returns the file size in bytes (useful for logging / diagnostics).
  static Future<int> fileSize(String filePath) async {
    final File file = File(filePath);
    if (!await file.exists()) return 0;
    return file.length();
  }
}
