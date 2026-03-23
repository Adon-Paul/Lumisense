import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Identifies Indian currency denominations from camera images using Gemini
/// Vision API.
///
/// Sends a JPEG frame to Gemini with a specialised prompt and returns a
/// concise, TTS-friendly denomination string.
class CurrencyDetectorService {
  CurrencyDetectorService({required String apiKey}) : _apiKey = apiKey;

  final String _apiKey;

  static const String _model = 'gemini-2.0-flash';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';
  static const Duration _timeout = Duration(seconds: 20);
  static const int _maxRetries = 2;

  /// Prompt engineered specifically for Indian currency note identification.
  static const String _currencyPrompt =
      'You are a currency identification assistant for a visually impaired person. '
      'Look at this image and determine if it contains an Indian currency note (₹). '
      'If you see a currency note, respond with ONLY the denomination in this exact format: '
      '"This is a [amount] rupee note." where [amount] is 10, 20, 50, 100, 200, 500, or 2000. '
      'If you see multiple notes, list each one. '
      'If you see coins, identify them similarly: "This is a [amount] rupee coin." '
      'If there is no currency visible, respond: "No currency detected. Please hold the note closer to the camera." '
      'Keep your response under 2 sentences. Be confident and clear.';

  /// Identifies Indian currency notes from a JPEG image.
  ///
  /// Returns a TTS-friendly string describing the denomination(s) found.
  Future<String> identifyCurrency(Uint8List jpegBytes) async {
    if (_apiKey.trim().isEmpty) {
      return 'No Gemini API key configured. Please add your key in Settings.';
    }

    final String base64Image = base64Encode(jpegBytes);
    final Uri uri =
        Uri.parse('$_baseUrl/$_model:generateContent?key=$_apiKey');

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
              'text': _currencyPrompt,
            },
          ],
        },
      ],
      'generationConfig': <String, dynamic>{
        'maxOutputTokens': 100,
        'temperature': 0.2,
      },
    };

    final String jsonBody = jsonEncode(requestBody);

    http.Response? response;
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        response = await http
            .post(
              uri,
              headers: <String, String>{'Content-Type': 'application/json'},
              body: jsonBody,
            )
            .timeout(_timeout);

        if (response.statusCode == 429 || response.statusCode >= 500) {
          debugPrint(
              'CurrencyDetector: transient error ${response.statusCode} '
              '(attempt $attempt/$_maxRetries)');
          if (attempt < _maxRetries) {
            await Future<void>.delayed(Duration(seconds: attempt * 2));
            continue;
          }
        }
        break;
      } on TimeoutException {
        debugPrint('CurrencyDetector: timeout (attempt $attempt/$_maxRetries)');
        if (attempt >= _maxRetries) {
          return 'Currency detection timed out. Please try again.';
        }
        await Future<void>.delayed(Duration(seconds: attempt));
      } on SocketException {
        return 'No internet connection. Currency detection requires internet.';
      } catch (e) {
        debugPrint('CurrencyDetector: error: $e');
        return 'Currency detection failed. Please try again.';
      }
    }

    if (response == null || response.statusCode != 200) {
      return 'Currency detection failed. Please try again.';
    }

    return _extractText(response.body);
  }

  String _extractText(String responseBody) {
    try {
      final Map<String, dynamic> json =
          jsonDecode(responseBody) as Map<String, dynamic>;
      final List<dynamic>? candidates =
          json['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        return 'Could not identify currency. Please try again.';
      }
      final Map<String, dynamic> candidate =
          candidates.first as Map<String, dynamic>;
      final Map<String, dynamic>? content =
          candidate['content'] as Map<String, dynamic>?;
      final List<dynamic>? parts = content?['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) {
        return 'Could not identify currency. Please try again.';
      }
      final String? text =
          (parts.first as Map<String, dynamic>)['text'] as String?;
      return text?.trim() ?? 'Could not identify currency. Please try again.';
    } catch (_) {
      return 'Could not identify currency. Please try again.';
    }
  }
}
