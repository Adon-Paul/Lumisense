import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  bool _isReady = false;
  bool _cancelled = false;

  /// Cached loading future to prevent concurrent loadModel() races.
  Future<bool>? _loadFuture;

  bool get isReady => _isReady;
  bool get isLoading => _loadFuture != null;

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

  /// Lookup map for quick tool resolution by name.
  static final Map<String, ToolDefinition> _toolsByName = {
    for (final tool in _appTools) tool.name: tool,
  };

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

  /// Loads the Gemma 3n E2B model. Safe to call concurrently — only one
  /// load operation runs at a time.
  Future<bool> loadModel() =>
      _loadFuture ??= _doLoadModel().whenComplete(() => _loadFuture = null);

  Future<bool> _doLoadModel() async {
    if (_isReady) return true;

    final ready =
        await _modelManager.isModelReady(OnDeviceModel.gemma3nAssistant);
    if (!ready) {
      final mPath =
          await _modelManager.modelPath(OnDeviceModel.gemma3nAssistant);
      debugPrint('Gemma 3n E2B: model not ready');
      debugPrint('  Model path: $mPath exists=${File(mPath).existsSync()}');
      return false;
    }

    try {
      final mPath =
          await _modelManager.modelPath(OnDeviceModel.gemma3nAssistant);

      debugPrint('Gemma 3n E2B: loading model from $mPath '
          '(${(File(mPath).lengthSync() / 1024 / 1024).toStringAsFixed(0)}MB)');

      _engine = LlamaEngine(LlamaBackend());
      await _engine!.loadModel(mPath);

      _session = ChatSession(
        _engine!,
        systemPrompt: _systemPrompt,
      );

      _isReady = true;
      debugPrint('Gemma 3n E2B assistant model loaded successfully');
      return true;
    } catch (e, stack) {
      debugPrint('Failed to load Gemma 3n E2B: $e');
      debugPrint('Stack: $stack');
      try {
        await _engine?.dispose();
      } catch (_) {}
      _engine = null;
      _session = null;
      _isReady = false;
      return false;
    }
  }

  /// Unloads the model to free RAM.
  Future<void> unload() async {
    _cancelled = true;
    _session = null;
    if (_engine != null) {
      await _engine!.dispose();
      _engine = null;
    }
    _isReady = false;
    _cancelled = false;
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

  /// Cancels any in-progress inference.
  void cancelInference() {
    _cancelled = true;
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Processes a user message and returns an [AssistantResponse].
  ///
  /// Properly handles llamadart's tool-calling protocol:
  /// 1. Streams the model's response, accumulating text AND tool call deltas
  /// 2. If tool calls are present, invokes the matching handlers
  /// 3. Feeds tool results back to the session via addMessage
  /// 4. Streams the model's follow-up response
  /// 5. Parses action markers from handler return values
  Future<AssistantResponse> processMessage(String userMessage) async {
    if (!_isReady || _session == null) {
      throw const OnDeviceAssistantException(
        'Assistant model not loaded. Please download it in Settings.',
      );
    }

    _cancelled = false;

    try {
      // Phase 1: Stream initial response, collecting text + tool calls
      final result = await _streamAndCollect(
        [LlamaTextContent(userMessage)],
      );

      if (_cancelled) {
        return const AssistantResponse(
            text: 'Request cancelled.');
      }

      // Phase 2: If tool calls were made, invoke handlers and get follow-up
      if (result.toolCalls.isNotEmpty) {
        return await _handleToolCalls(result);
      }

      // Phase 3: Pure conversational response
      final text = result.textBuffer.toString().trim();
      return AssistantResponse(text: text.isNotEmpty ? text : null);
    } catch (e) {
      if (e is OnDeviceAssistantException) rethrow;
      debugPrint('Assistant inference error: $e');
      throw OnDeviceAssistantException(
        'Assistant failed: ${e.toString().split('\n').first}',
      );
    }
  }

  /// Streaming version of [processMessage] for real-time TTS.
  ///
  /// Yields text tokens as they arrive. If the model makes a tool call,
  /// the handler result is yielded as a single chunk followed by the
  /// model's follow-up text.
  Stream<String> processMessageStream(String userMessage) async* {
    if (!_isReady || _session == null) {
      throw const OnDeviceAssistantException(
        'Assistant model not loaded.',
      );
    }

    _cancelled = false;

    // Phase 1: Stream initial response
    final toolCallBuilders = <int, _ToolCallBuilder>{};
    final textBuffer = StringBuffer();

    await for (final chunk in _session!.create(
      [LlamaTextContent(userMessage)],
      tools: _appTools,
    )) {
      if (_cancelled) return;

      final delta = chunk.choices.first.delta;

      // Yield text tokens immediately for TTS
      if (delta.content != null) {
        textBuffer.write(delta.content);
        yield delta.content!;
      }

      // Accumulate tool call deltas
      _accumulateToolCalls(delta, toolCallBuilders);
    }

    // Phase 2: If tool calls present, invoke and yield results
    if (toolCallBuilders.isNotEmpty) {
      final toolResults = await _invokeToolHandlers(toolCallBuilders);

      // Feed results back to the session
      for (final result in toolResults) {
        _session!.addMessage(LlamaChatMessage.withContent(
          role: LlamaChatRole.tool,
          content: [result.toolResultContent],
        ));
      }

      // Stream model's follow-up response
      await for (final chunk in _session!.create([], tools: _appTools)) {
        if (_cancelled) return;
        final content = chunk.choices.first.delta.content;
        if (content != null) yield content;
      }
    }
  }

  // ─── Tool Call Handling ────────────────────────────────────────────────────

  /// Streams a session response, collecting text and tool call deltas.
  Future<_StreamResult> _streamAndCollect(
    List<LlamaContentPart> parts,
  ) async {
    final toolCallBuilders = <int, _ToolCallBuilder>{};
    final textBuffer = StringBuffer();

    await for (final chunk in _session!.create(
      parts,
      tools: _appTools,
    )) {
      if (_cancelled) break;

      final delta = chunk.choices.first.delta;

      if (delta.content != null) {
        textBuffer.write(delta.content);
      }

      _accumulateToolCalls(delta, toolCallBuilders);
    }

    return _StreamResult(
      textBuffer: textBuffer,
      toolCalls: toolCallBuilders,
    );
  }

  /// Accumulates tool call delta chunks into builders keyed by index.
  void _accumulateToolCalls(
    LlamaCompletionChunkDelta delta,
    Map<int, _ToolCallBuilder> builders,
  ) {
    if (delta.toolCalls == null) return;

    for (final tc in delta.toolCalls!) {
      builders.putIfAbsent(tc.index, () => _ToolCallBuilder());
      final builder = builders[tc.index]!;
      if (tc.id != null) builder.id = tc.id;
      if (tc.type != null) builder.type = tc.type;
      if (tc.function?.name != null) builder.name = tc.function!.name;
      if (tc.function?.arguments != null) {
        builder.argumentsBuffer.write(tc.function!.arguments!);
      }
    }
  }

  /// Invokes tool handlers for all accumulated tool calls.
  Future<List<_ToolResult>> _invokeToolHandlers(
    Map<int, _ToolCallBuilder> builders,
  ) async {
    final results = <_ToolResult>[];
    final sortedIndices = builders.keys.toList()..sort();

    for (final index in sortedIndices) {
      final builder = builders[index]!;
      final toolName = builder.name ?? '';
      final tool = _toolsByName[toolName];

      if (tool == null) {
        debugPrint('Unknown tool call: $toolName');
        results.add(_ToolResult(
          id: builder.id,
          name: toolName,
          handlerResult: 'Error: Unknown function "$toolName"',
          toolResultContent: LlamaToolResultContent(
            id: builder.id,
            name: toolName,
            result: 'Error: Unknown function "$toolName"',
          ),
        ));
        continue;
      }

      // Parse accumulated JSON arguments
      Map<String, dynamic> args = {};
      final rawArgs = builder.argumentsBuffer.toString();
      if (rawArgs.isNotEmpty) {
        try {
          args = jsonDecode(rawArgs) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('Failed to parse tool call args for $toolName: $e');
        }
      }

      // Invoke the handler
      final handlerResult = await tool.invoke(args);
      final resultStr = handlerResult?.toString() ?? '';

      results.add(_ToolResult(
        id: builder.id,
        name: toolName,
        handlerResult: resultStr,
        toolResultContent: LlamaToolResultContent(
          id: builder.id,
          name: toolName,
          result: resultStr,
        ),
      ));
    }

    return results;
  }

  /// Handles tool calls: invokes handlers, feeds results back, gets follow-up.
  Future<AssistantResponse> _handleToolCalls(_StreamResult result) async {
    final toolResults = await _invokeToolHandlers(result.toolCalls);

    // Extract action from handler results (first tool call with an action wins)
    AppAction? action;
    String? actionParam;
    for (final tr in toolResults) {
      final parsed = _parseActionMarker(tr.handlerResult);
      if (parsed != null) {
        action = parsed.action;
        actionParam = parsed.actionParam;
        break;
      }
    }

    // Feed tool results back to the session
    for (final tr in toolResults) {
      _session!.addMessage(LlamaChatMessage.withContent(
        role: LlamaChatRole.tool,
        content: [tr.toolResultContent],
      ));
    }

    // Get model's follow-up response
    final followUp = await _streamAndCollect([]);
    final followUpText = followUp.textBuffer.toString().trim();

    // Combine initial text + follow-up text
    final initialText = result.textBuffer.toString().trim();
    final combinedText = [
      if (initialText.isNotEmpty) initialText,
      if (followUpText.isNotEmpty) followUpText,
    ].join(' ').trim();

    return AssistantResponse(
      text: combinedText.isNotEmpty ? combinedText : null,
      action: action,
      actionParam: actionParam,
    );
  }

  // ─── Response Parsing ───────────────────────────────────────────────────────

  /// Parses an `__ACTION:name[:param]` marker from a tool handler result.
  static _ActionParsed? _parseActionMarker(String raw) {
    final match = RegExp(r'__ACTION:(\w+)(?::(.+))?').firstMatch(raw);
    if (match == null) return null;
    return _ActionParsed(
      action: AppAction.fromString(match.group(1)!),
      actionParam: match.group(2),
    );
  }
}

// ─── Internal Helper Classes ─────────────────────────────────────────────────

/// Accumulates streaming tool call chunks.
class _ToolCallBuilder {
  String? id;
  String? type;
  String? name;
  final StringBuffer argumentsBuffer = StringBuffer();
}

/// Result of streaming a session response.
class _StreamResult {
  _StreamResult({required this.textBuffer, required this.toolCalls});
  final StringBuffer textBuffer;
  final Map<int, _ToolCallBuilder> toolCalls;
}

/// Result of invoking a tool handler.
class _ToolResult {
  _ToolResult({
    required this.id,
    required this.name,
    required this.handlerResult,
    required this.toolResultContent,
  });
  final String? id;
  final String name;
  final String handlerResult;
  final LlamaToolResultContent toolResultContent;
}

/// Parsed action marker from a handler result string.
class _ActionParsed {
  _ActionParsed({required this.action, required this.actionParam});
  final AppAction? action;
  final String? actionParam;
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
