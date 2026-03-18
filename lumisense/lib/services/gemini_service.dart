import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Sends images to the Google Gemini Vision API and returns rich scene
/// descriptions tailored for visually impaired users.
///
/// Usage:
/// ```dart
/// final service = GeminiService(apiKey: 'YOUR_KEY');
/// final description = await service.describeScene(jpegBytes);
/// ```
class GeminiService {
  GeminiService({required String apiKey}) : _apiKey = apiKey;

  final String _apiKey;

  /// Model to use. `gemini-2.0-flash` balances quality and speed.
  static const String _model = 'gemini-2.0-flash';

  /// Base URL for the Generative Language API.
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// The system prompt engineered for accessibility scene description.
  static const String _scenePrompt =
      'You are an assistant for a visually impaired person. '
      'Describe what you see in this image in 2-3 clear, concise sentences. '
      'Focus on: what objects are present, their spatial arrangement, any text '
      'visible, and potential hazards or obstacles. '
      'Be specific about directions (left, right, ahead, behind). '
      'Use simple language that is easy to understand when spoken aloud.';

  /// Timeout for a single API call.
  static const Duration _timeout = Duration(seconds: 30);

  bool get hasApiKey => _apiKey.trim().isNotEmpty;

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Sends a JPEG image to Gemini and returns a scene description string.
  ///
  /// Throws [GeminiApiException] on HTTP errors, missing key, or bad response.
  Future<String> describeScene(Uint8List jpegBytes) async {
    if (!hasApiKey) {
      throw const GeminiApiException(
        'No Gemini API key configured. Please add your key in Settings.',
      );
    }

    final String base64Image = base64Encode(jpegBytes);

    final Uri uri = Uri.parse('$_baseUrl/$_model:generateContent?key=$_apiKey');

    final Map<String, dynamic> requestBody = <String, dynamic>{
      'contents': <Map<String, dynamic>>[
        <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{
              'inlineData': <String, String>{
                'mimeType': 'image/jpeg',
                'data': base64Image,
              },
            },
            <String, dynamic>{
              'text': _scenePrompt,
            },
          ],
        },
      ],
      // Safety settings: keep defaults. Generation config for conciseness.
      'generationConfig': <String, dynamic>{
        'maxOutputTokens': 256,
        'temperature': 0.4,
      },
    };

    final http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const GeminiApiException(
        'The request timed out. Please try again.',
      );
    } on SocketException {
      throw const GeminiApiException(
        'No internet connection. Please check your network and try again.',
      );
    } on http.ClientException {
      throw const GeminiApiException(
        'Network error. Please check your connection and try again.',
      );
    }

    if (response.statusCode != 200) {
      final String detail = _parseErrorDetail(response);
      debugPrint(
        'Gemini API error ${response.statusCode}: ${response.body}',
      );
      throw GeminiApiException(
        'Gemini API error (${response.statusCode}). $detail',
      );
    }

    return _extractText(response.body);
  }

  /// Sends a JPEG file to Gemini for scene description.
  Future<String> describeSceneFromFile(String filePath) async {
    final File file = File(filePath);
    if (!await file.exists()) {
      throw const GeminiApiException('Image file not found.');
    }
    final Uint8List bytes = await file.readAsBytes();
    return describeScene(bytes);
  }

  // ─── Private helpers ─────────────────────────────────────────────────────

  /// Extracts the text response from the Gemini JSON body.
  String _extractText(String responseBody) {
    try {
      final Map<String, dynamic> json =
          jsonDecode(responseBody) as Map<String, dynamic>;

      final List<dynamic>? candidates =
          json['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        // Check for prompt-blocked response
        final Map<String, dynamic>? promptFeedback =
            json['promptFeedback'] as Map<String, dynamic>?;
        if (promptFeedback != null) {
          final String? blockReason =
              promptFeedback['blockReason'] as String?;
          if (blockReason != null) {
            throw GeminiApiException(
              'The image was blocked by safety filters ($blockReason). '
              'Please try a different scene.',
            );
          }
        }
        throw const GeminiApiException(
          'No description was generated. Please try again.',
        );
      }

      final Map<String, dynamic> candidate =
          candidates.first as Map<String, dynamic>;
      final Map<String, dynamic>? content =
          candidate['content'] as Map<String, dynamic>?;
      final List<dynamic>? parts =
          content?['parts'] as List<dynamic>?;

      if (parts == null || parts.isEmpty) {
        throw const GeminiApiException(
          'Empty response from Gemini. Please try again.',
        );
      }

      final String? text =
          (parts.first as Map<String, dynamic>)['text'] as String?;
      if (text == null || text.trim().isEmpty) {
        throw const GeminiApiException(
          'Gemini returned an empty description. Please try again.',
        );
      }

      return text.trim();
    } on FormatException {
      throw const GeminiApiException(
        'Unexpected response format from Gemini.',
      );
    }
  }

  /// Extracts a human-readable detail from an error response.
  String _parseErrorDetail(http.Response response) {
    try {
      final Map<String, dynamic> json =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic>? error =
          json['error'] as Map<String, dynamic>?;
      return (error?['message'] as String?) ?? '';
    } catch (_) {
      return '';
    }
  }
}

/// Exception type for Gemini API errors with user-friendly messages.
class GeminiApiException implements Exception {
  const GeminiApiException(this.message);

  final String message;

  @override
  String toString() => 'GeminiApiException: $message';
}
