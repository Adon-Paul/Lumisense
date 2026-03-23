import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';

import 'model_manager.dart';

/// On-device conversational assistant powered by Gemma 3n E2B.
///
/// Provides:
/// - Multi-turn conversation with context
/// - Function calling to invoke app features by natural language
/// - Fully offline — no API keys, no network
///
/// The function-calling model interprets user intent and returns structured
/// tool calls that the orchestrator maps to actual app actions.
class OnDeviceAssistantService {
  OnDeviceAssistantService({required ModelManager modelManager})
      : _modelManager = modelManager;

  final ModelManager _modelManager;

  LlamaEngine? _engine;
  ChatSession? _session;
  bool _isLoading = false;
  bool _isReady = false;

  bool get isReady => _isReady;
  bool get isLoading => _isLoading;

  // ─── Tool Definitions ───────────────────────────────────────────────────────

  /// App functions the assistant can invoke.
  static final List<ToolDefinition> _appTools = [
    ToolDefinition(
      name: 'describe_scene',
      description:
          'Take a photo and describe what the camera sees. Use when the user '
          'asks what is in front of them, what they are looking at, or wants '
          'a scene description.',
      parameters: [],
      handler: (_) async => '__ACTION:describe_scene',
    ),
    ToolDefinition(
      name: 'read_text',
      description:
          'Read text visible in the camera view using OCR. Use when the user '
          'wants to read a sign, document, label, or any printed text.',
      parameters: [],
      handler: (_) async => '__ACTION:read_text',
    ),
    ToolDefinition(
      name: 'identify_currency',
      description:
          'Identify banknotes or coins in the camera view. Use when the user '
          'asks about money, bills, or currency denominations.',
      parameters: [],
      handler: (_) async => '__ACTION:identify_currency',
    ),
    ToolDefinition(
      name: 'detect_people',
      description:
          'Detect and describe people in the camera view using face and pose '
          'detection. Use when the user asks who is there or about people nearby.',
      parameters: [],
      handler: (_) async => '__ACTION:detect_people',
    ),
    ToolDefinition(
      name: 'check_brightness',
      description:
          'Check the ambient light level. Use when the user asks if lights '
          'are on, if it is dark, or about brightness.',
      parameters: [],
      handler: (_) async => '__ACTION:check_brightness',
    ),
    ToolDefinition(
      name: 'get_weather',
      description:
          'Get the current weather and forecast. Use when the user asks about '
          'weather, temperature, rain, or outdoor conditions.',
      parameters: [],
      handler: (_) async => '__ACTION:get_weather',
    ),
    ToolDefinition(
      name: 'call_contact',
      description:
          'Make a phone call to a contact. Use when the user wants to call '
          'someone.',
      parameters: [
        ToolParam.string('name',
            description: 'Name of the contact to call', required: true),
      ],
      handler: (params) async {
        final name = params.getRequiredString('name');
        return '__ACTION:call_contact:$name';
      },
    ),
    ToolDefinition(
      name: 'send_sos',
      description:
          'Send an emergency SOS message with location. Use when the user '
          'says they need help, emergency, or SOS.',
      parameters: [],
      handler: (_) async => '__ACTION:send_sos',
    ),
    ToolDefinition(
      name: 'navigate',
      description:
          'Start navigation mode with obstacle detection. Use when the user '
          'wants to walk somewhere or needs navigation help.',
      parameters: [],
      handler: (_) async => '__ACTION:navigate',
    ),
    ToolDefinition(
      name: 'scan_qr',
      description:
          'Scan a QR code or barcode. Use when the user mentions QR codes, '
          'barcodes, scanning, or UPI payments.',
      parameters: [],
      handler: (_) async => '__ACTION:scan_qr',
    ),
  ];

  // ─── System Prompt ──────────────────────────────────────────────────────────

  static const String _systemPrompt =
      'You are LumiSense, an AI assistant for visually impaired people. '
      'You run entirely on the user\'s phone with no internet needed. '
      'You can invoke app functions using the tools provided. '
      'When the user asks to do something the app can handle, use the '
      'appropriate tool. For general questions, respond conversationally '
      'in 1-2 sentences. Be warm, helpful, and concise — your responses '
      'will be read aloud via text-to-speech.';

  // ─── Lifecycle ──────────────────────────────────────────────────────────────

  /// Loads the Gemma 3n E2B model. Call once before using.
  Future<bool> loadModel() async {
    if (_isReady) return true;
    if (_isLoading) return false;

    final ready =
        await _modelManager.isModelReady(OnDeviceModel.gemma3nAssistant);
    if (!ready) {
      debugPrint('Gemma 3n E2B model not downloaded yet');
      return false;
    }

    _isLoading = true;
    try {
      final mPath =
          await _modelManager.modelPath(OnDeviceModel.gemma3nAssistant);

      _engine = LlamaEngine(LlamaBackend());
      await _engine!.loadModel(mPath);

      _session = ChatSession(
        _engine!,
        systemPrompt: _systemPrompt,
      );

      _isReady = true;
      debugPrint('Gemma 3n E2B assistant model loaded successfully');
      return true;
    } catch (e) {
      debugPrint('Failed to load Gemma 3n E2B: $e');
      _engine = null;
      _session = null;
      _isReady = false;
      return false;
    } finally {
      _isLoading = false;
    }
  }

  /// Unloads the model to free RAM.
  Future<void> unload() async {
    _session = null;
    if (_engine != null) {
      await _engine!.dispose();
      _engine = null;
    }
    _isReady = false;
  }

  /// Resets conversation history (starts fresh context).
  void resetConversation() {
    if (_engine != null && _isReady) {
      _session = ChatSession(
        _engine!,
        systemPrompt: _systemPrompt,
      );
    }
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Processes a user message and returns an [AssistantResponse].
  ///
  /// The response may contain:
  /// - A text reply (for conversational responses)
  /// - A tool call action (for app function invocations)
  /// - Both (tool call with explanatory text)
  Future<AssistantResponse> processMessage(String userMessage) async {
    if (!_isReady || _session == null) {
      throw const OnDeviceAssistantException(
        'Assistant model not loaded. Please download it in Settings.',
      );
    }

    try {
      final buffer = StringBuffer();
      await for (final chunk in _session!.create(
        [LlamaTextContent(userMessage)],
        tools: _appTools,
      )) {
        final content = chunk.choices.first.delta.content;
        if (content != null) buffer.write(content);
      }

      final rawResponse = buffer.toString().trim();
      return _parseResponse(rawResponse);
    } catch (e) {
      if (e is OnDeviceAssistantException) rethrow;
      debugPrint('Assistant inference error: $e');
      throw OnDeviceAssistantException(
        'Assistant failed: ${e.toString().split('\n').first}',
      );
    }
  }

  /// Streaming version of [processMessage] for real-time TTS.
  Stream<String> processMessageStream(String userMessage) async* {
    if (!_isReady || _session == null) {
      throw const OnDeviceAssistantException(
        'Assistant model not loaded.',
      );
    }

    await for (final chunk in _session!.create(
      [LlamaTextContent(userMessage)],
      tools: _appTools,
    )) {
      final content = chunk.choices.first.delta.content;
      if (content != null) yield content;
    }
  }

  // ─── Response Parsing ───────────────────────────────────────────────────────

  AssistantResponse _parseResponse(String raw) {
    // Check for action markers from tool handlers
    if (raw.contains('__ACTION:')) {
      final actionMatch = RegExp(r'__ACTION:(\w+)(?::(.+))?').firstMatch(raw);
      if (actionMatch != null) {
        final action = actionMatch.group(1)!;
        final param = actionMatch.group(2);
        // Strip action markers from text
        final text = raw.replaceAll(RegExp(r'__ACTION:\w+(?::[^\s]+)?'), '').trim();
        return AssistantResponse(
          text: text.isNotEmpty ? text : null,
          action: AppAction.fromString(action),
          actionParam: param,
        );
      }
    }

    // Try parsing as JSON tool call (some models output JSON directly)
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded.containsKey('name')) {
        final name = decoded['name'] as String;
        final args = decoded['arguments'] as Map<String, dynamic>?;
        return AssistantResponse(
          action: AppAction.fromString(name),
          actionParam: args?['name'] as String?,
        );
      }
    } catch (_) {
      // Not JSON — treat as plain text
    }

    // Pure conversational response
    return AssistantResponse(text: raw.isNotEmpty ? raw : null);
  }
}

// ─── Data Classes ─────────────────────────────────────────────────────────────

/// Structured response from the on-device assistant.
class AssistantResponse {
  const AssistantResponse({this.text, this.action, this.actionParam});

  /// Conversational text to speak via TTS.
  final String? text;

  /// App action to invoke (null if purely conversational).
  final AppAction? action;

  /// Optional parameter for the action (e.g., contact name for call_contact).
  final String? actionParam;

  bool get hasAction => action != null;
  bool get hasText => text != null && text!.isNotEmpty;
}

/// App actions the assistant can trigger.
enum AppAction {
  describeScene,
  readText,
  identifyCurrency,
  detectPeople,
  checkBrightness,
  getWeather,
  callContact,
  sendSos,
  navigate,
  scanQr;

  static AppAction? fromString(String name) {
    switch (name) {
      case 'describe_scene':
        return AppAction.describeScene;
      case 'read_text':
        return AppAction.readText;
      case 'identify_currency':
        return AppAction.identifyCurrency;
      case 'detect_people':
        return AppAction.detectPeople;
      case 'check_brightness':
        return AppAction.checkBrightness;
      case 'get_weather':
        return AppAction.getWeather;
      case 'call_contact':
        return AppAction.callContact;
      case 'send_sos':
        return AppAction.sendSos;
      case 'navigate':
        return AppAction.navigate;
      case 'scan_qr':
        return AppAction.scanQr;
      default:
        return null;
    }
  }
}

/// Exception for assistant model errors.
class OnDeviceAssistantException implements Exception {
  const OnDeviceAssistantException(this.message);
  final String message;

  @override
  String toString() => 'OnDeviceAssistantException: $message';
}
