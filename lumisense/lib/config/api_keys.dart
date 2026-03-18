class ApiKeys {
  ApiKeys._();

  // Supply with: --dart-define=GEMINI_API_KEY=your_real_key
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  static bool get hasGeminiKey => geminiApiKey.trim().isNotEmpty;
}
