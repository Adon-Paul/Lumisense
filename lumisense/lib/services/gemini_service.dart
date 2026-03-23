import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Multi-provider AI vision service with automatic fallback chain:
/// Gemini → OpenRouter → Groq → Ollama (local).
///
/// Sends images to the first available provider and falls through to the
/// next on failure. All providers return scene descriptions for TTS.
class GeminiService {
  GeminiService({
    required String apiKey,
    String openRouterApiKey = '',
    String groqApiKey = '',
    String ollamaServerUrl = '',
  })  : _apiKey = apiKey,
        _openRouterApiKey = openRouterApiKey,
        _groqApiKey = groqApiKey,
        _ollamaServerUrl = ollamaServerUrl;

  final String _apiKey;
  final String _openRouterApiKey;
  final String _groqApiKey;
  final String _ollamaServerUrl;

  // ─── Constants ────────────────────────────────────────────────────────────

  static const String _geminiModel = 'gemini-2.0-flash';
  static const String _geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  static const String _openRouterBaseUrl =
      'https://openrouter.ai/api/v1/chat/completions';
  static const List<String> _openRouterModels = <String>[
    'google/gemini-2.0-flash-exp:free',
    'meta-llama/llama-3.2-11b-vision-instruct:free',
    'google/gemini-flash-1.5-8b',
  ];

  static const String _groqBaseUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _groqModel = 'llama-3.2-11b-vision-preview';

  /// Default Ollama vision model (moondream — small + fast, ~1.8GB).
  static const String _ollamaModel = 'moondream';

  static const String _scenePrompt =
      'You are an assistant for a visually impaired person. '
      'Describe what you see in this image in 2-3 clear, concise sentences. '
      'Focus on: what objects are present, their spatial arrangement, any text '
      'visible, and potential hazards or obstacles. '
      'Be specific about directions (left, right, ahead, behind). '
      'Use simple language that is easy to understand when spoken aloud.';

  static const Duration _timeout = Duration(seconds: 30);
  static const int _maxRetries = 3;

  bool get hasApiKey => _apiKey.trim().isNotEmpty;
  bool get hasOpenRouterFallback => _openRouterApiKey.trim().isNotEmpty;
  bool get hasGroqFallback => _groqApiKey.trim().isNotEmpty;
  bool get hasOllamaFallback => _ollamaServerUrl.trim().isNotEmpty;

  DateTime lastCallTime = DateTime(2000);

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sends a JPEG image and returns a scene description.
  ///
  /// Tries providers in order: Gemini → OpenRouter → Groq → Ollama.
  /// Throws [GeminiApiException] only if ALL configured providers fail.
  Future<String> describeScene(Uint8List jpegBytes) async {
    GeminiApiException? lastError;

    // 1. Gemini
    if (hasApiKey) {
      try {
        final String result = await _callGemini(jpegBytes);
        lastCallTime = DateTime.now();
        return result;
      } on GeminiApiException catch (e) {
        debugPrint('Gemini failed: ${e.message}');
        lastError = e;
      }
    }

    // 2. OpenRouter
    if (hasOpenRouterFallback) {
      try {
        debugPrint('Falling back to OpenRouter...');
        final String result = await _callOpenRouter(jpegBytes);
        lastCallTime = DateTime.now();
        return result;
      } on GeminiApiException catch (e) {
        debugPrint('OpenRouter failed: ${e.message}');
        lastError = e;
      }
    }

    // 3. Groq
    if (hasGroqFallback) {
      try {
        debugPrint('Falling back to Groq...');
        final String result = await _callGroq(jpegBytes);
        lastCallTime = DateTime.now();
        return result;
      } on GeminiApiException catch (e) {
        debugPrint('Groq failed: ${e.message}');
        lastError = e;
      }
    }

    // 4. Ollama (local)
    if (hasOllamaFallback) {
      try {
        debugPrint('Falling back to Ollama...');
        final String result = await _callOllama(jpegBytes);
        lastCallTime = DateTime.now();
        return result;
      } on GeminiApiException catch (e) {
        debugPrint('Ollama failed: ${e.message}');
        lastError = e;
      }
    }

    // All failed.
    if (lastError != null) throw lastError;
    throw const GeminiApiException(
      'No AI provider configured. Please add at least one API key in Settings.',
    );
  }

  Future<String> describeSceneFromFile(String filePath) async {
    final File file = File(filePath);
    if (!await file.exists()) {
      throw const GeminiApiException('Image file not found.');
    }
    return describeScene(await file.readAsBytes());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GEMINI
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> _callGemini(Uint8List jpegBytes) async {
    final String base64Image = base64Encode(jpegBytes);
    final Uri uri = Uri.parse(
        '$_geminiBaseUrl/$_geminiModel:generateContent?key=$_apiKey');

    final Map<String, dynamic> body = <String, dynamic>{
      'contents': <Map<String, dynamic>>[
        <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{
              'inlineData': <String, String>{
                'mimeType': 'image/jpeg',
                'data': base64Image,
              },
            },
            <String, dynamic>{'text': _scenePrompt},
          ],
        },
      ],
      'generationConfig': <String, dynamic>{
        'maxOutputTokens': 256,
        'temperature': 0.4,
      },
    };

    http.Response? response;
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        response = await http
            .post(uri,
                headers: <String, String>{'Content-Type': 'application/json'},
                body: jsonEncode(body))
            .timeout(_timeout);

        if (response.statusCode == 429 || response.statusCode >= 500) {
          debugPrint('Gemini ${response.statusCode} attempt $attempt');
          if (attempt < _maxRetries) {
            await Future<void>.delayed(Duration(seconds: attempt * 2));
            continue;
          }
        }
        break;
      } on TimeoutException {
        if (attempt >= _maxRetries) {
          throw const GeminiApiException('Gemini timed out.');
        }
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      } on SocketException {
        throw const GeminiApiException('No internet connection.');
      } on http.ClientException {
        throw const GeminiApiException('Network error.');
      }
    }

    if (response == null) {
      throw const GeminiApiException('Unable to reach Gemini.');
    }
    if (response.statusCode != 200) {
      throw GeminiApiException(
          'Gemini error (${response.statusCode}). ${_parseErrorDetail(response)}');
    }

    return _extractGeminiText(response.body);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OPENROUTER (OpenAI-compatible, multiple free models)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> _callOpenRouter(Uint8List jpegBytes) async {
    final String base64Image = base64Encode(jpegBytes);
    GeminiApiException? lastError;

    for (final String model in _openRouterModels) {
      try {
        return await _callOpenAICompatible(
          url: _openRouterBaseUrl,
          apiKey: _openRouterApiKey,
          model: model,
          base64Image: base64Image,
          providerName: 'OpenRouter',
          extraHeaders: <String, String>{
            'HTTP-Referer': 'https://lumisense.app',
            'X-Title': 'LumiSense',
          },
        );
      } on GeminiApiException catch (e) {
        debugPrint('OpenRouter $model failed: ${e.message}');
        lastError = e;
      }
    }
    throw lastError ??
        const GeminiApiException('OpenRouter: all models failed.');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GROQ (OpenAI-compatible, ultra-fast inference)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> _callGroq(Uint8List jpegBytes) async {
    return _callOpenAICompatible(
      url: _groqBaseUrl,
      apiKey: _groqApiKey,
      model: _groqModel,
      base64Image: base64Encode(jpegBytes),
      providerName: 'Groq',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OLLAMA (local server, different API format)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> _callOllama(Uint8List jpegBytes) async {
    final String base64Image = base64Encode(jpegBytes);

    // Ollama uses a different API format: images in the message, not content array.
    final String url = _ollamaServerUrl.endsWith('/')
        ? '${_ollamaServerUrl}api/chat'
        : '$_ollamaServerUrl/api/chat';

    final Map<String, dynamic> body = <String, dynamic>{
      'model': _ollamaModel,
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'user',
          'content': _scenePrompt,
          'images': <String>[base64Image],
        },
      ],
      'stream': false,
    };

    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(url),
            headers: <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60)); // Ollama can be slow
    } on TimeoutException {
      throw const GeminiApiException(
          'Ollama server timed out. Is it running?');
    } on SocketException {
      throw const GeminiApiException(
          'Cannot reach Ollama server. Check the URL and ensure it is running.');
    } on http.ClientException {
      throw const GeminiApiException(
          'Cannot connect to Ollama server.');
    }

    if (response.statusCode != 200) {
      throw GeminiApiException(
          'Ollama error (${response.statusCode}). ${_parseErrorDetail(response)}');
    }

    return _extractOllamaText(response.body);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED: OpenAI-compatible request (used by OpenRouter + Groq)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> _callOpenAICompatible({
    required String url,
    required String apiKey,
    required String model,
    required String base64Image,
    required String providerName,
    Map<String, String>? extraHeaders,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'model': model,
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'user',
          'content': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'image_url',
              'image_url': <String, String>{
                'url': 'data:image/jpeg;base64,$base64Image',
              },
            },
            <String, dynamic>{
              'type': 'text',
              'text': _scenePrompt,
            },
          ],
        },
      ],
      'max_tokens': 256,
    };

    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
      ...?extraHeaders,
    };

    http.Response response;
    try {
      response = await http
          .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
          .timeout(_timeout);
    } on TimeoutException {
      throw GeminiApiException('$providerName timed out.');
    } on SocketException {
      throw const GeminiApiException('No internet connection.');
    } on http.ClientException {
      throw const GeminiApiException('Network error.');
    }

    if (response.statusCode == 429) {
      throw GeminiApiException('$providerName rate limit hit.');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw GeminiApiException('$providerName API key is invalid.');
    }
    if (response.statusCode != 200) {
      throw GeminiApiException(
          '$providerName error (${response.statusCode}). '
          '${_parseErrorDetail(response)}');
    }

    return _extractOpenAIText(response.body, providerName);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESPONSE PARSERS
  // ═══════════════════════════════════════════════════════════════════════════

  String _extractGeminiText(String responseBody) {
    try {
      final Map<String, dynamic> json =
          jsonDecode(responseBody) as Map<String, dynamic>;
      final List<dynamic>? candidates = json['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        final Map<String, dynamic>? feedback =
            json['promptFeedback'] as Map<String, dynamic>?;
        final String? reason = feedback?['blockReason'] as String?;
        if (reason != null) {
          throw GeminiApiException('Image blocked ($reason).');
        }
        throw const GeminiApiException('No description generated.');
      }
      final Map<String, dynamic> c = candidates.first as Map<String, dynamic>;
      final List<dynamic>? parts =
          (c['content'] as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
      final String? text =
          (parts?.first as Map<String, dynamic>?)?['text'] as String?;
      if (text == null || text.trim().isEmpty) {
        throw const GeminiApiException('Empty response from Gemini.');
      }
      return text.trim();
    } on FormatException {
      throw const GeminiApiException('Unexpected Gemini response format.');
    }
  }

  /// Parses OpenAI-compatible response (OpenRouter, Groq).
  String _extractOpenAIText(String responseBody, String provider) {
    try {
      final Map<String, dynamic> json =
          jsonDecode(responseBody) as Map<String, dynamic>;
      final List<dynamic>? choices = json['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        throw GeminiApiException('$provider returned no response.');
      }
      final String? content = ((choices.first
              as Map<String, dynamic>)['message'] as Map<String, dynamic>?)?[
          'content'] as String?;
      if (content == null || content.trim().isEmpty) {
        throw GeminiApiException('$provider returned empty description.');
      }
      return content.trim();
    } on FormatException {
      throw GeminiApiException('Unexpected $provider response format.');
    }
  }

  /// Parses Ollama chat response.
  String _extractOllamaText(String responseBody) {
    try {
      final Map<String, dynamic> json =
          jsonDecode(responseBody) as Map<String, dynamic>;
      final Map<String, dynamic>? message =
          json['message'] as Map<String, dynamic>?;
      final String? content = message?['content'] as String?;
      if (content == null || content.trim().isEmpty) {
        throw const GeminiApiException('Ollama returned empty response.');
      }
      return content.trim();
    } on FormatException {
      throw const GeminiApiException('Unexpected Ollama response format.');
    }
  }

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

/// Exception type for AI vision API errors with user-friendly messages.
class GeminiApiException implements Exception {
  const GeminiApiException(this.message);
  final String message;

  @override
  String toString() => 'GeminiApiException: $message';
}
