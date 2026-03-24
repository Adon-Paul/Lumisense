import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:lumisense/providers/settings_provider.dart';
import 'package:lumisense/services/model_manager.dart';
import 'package:lumisense/services/tts_service.dart';
import 'package:lumisense/utils/theme.dart';

/// Full settings screen exposing TTS controls, emergency contact, and Gemini
/// API key — all accessible with high-contrast UI and TTS announcements.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _emergencyContactController;
  late TextEditingController _apiKeyController;
  late TextEditingController _openRouterApiKeyController;
  late TextEditingController _groqApiKeyController;
  late TextEditingController _ollamaServerUrlController;
  late TextEditingController _orsApiKeyController;
  late TextEditingController _weatherApiKeyController;
  bool _apiKeyObscured = true;
  bool _openRouterApiKeyObscured = true;
  bool _groqApiKeyObscured = true;
  bool _orsApiKeyObscured = true;
  bool _weatherApiKeyObscured = true;

  /// Cached model readiness state, refreshed explicitly to avoid
  /// the FutureBuilder anti-pattern of recreating futures on every build.
  final Map<OnDeviceModel, bool> _modelReadyState = {
    for (final model in OnDeviceModel.values) model: false,
  };

  @override
  void initState() {
    super.initState();
    final SettingsProvider settings = context.read<SettingsProvider>();
    _emergencyContactController =
        TextEditingController(text: settings.emergencyContact);
    _apiKeyController = TextEditingController(text: settings.apiKey);
    _openRouterApiKeyController =
        TextEditingController(text: settings.openRouterApiKey);
    _groqApiKeyController = TextEditingController(text: settings.groqApiKey);
    _ollamaServerUrlController =
        TextEditingController(text: settings.ollamaServerUrl);
    _orsApiKeyController = TextEditingController(text: settings.orsApiKey);
    _weatherApiKeyController =
        TextEditingController(text: settings.weatherApiKey);

    // Load model readiness state once on init
    _refreshModelReadyState();

    // Announce screen to TTS for accessibility
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<TtsService>().speak('Settings. Adjust speech, emergency contact, and A I key.');
      }
    });
  }

  Future<void> _refreshModelReadyState() async {
    final modelMgr = context.read<ModelManager>();
    for (final model in OnDeviceModel.values) {
      _modelReadyState[model] = await modelMgr.isModelReady(model);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _emergencyContactController.dispose();
    _apiKeyController.dispose();
    _openRouterApiKeyController.dispose();
    _groqApiKeyController.dispose();
    _ollamaServerUrlController.dispose();
    _orsApiKeyController.dispose();
    _weatherApiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SettingsProvider settings = context.watch<SettingsProvider>();

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const Text('Settings'),
        leading: Semantics(
          label: 'Go back',
          button: true,
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: <Widget>[
          // ── TTS Section ──────────────────────────────────────────────
          _buildSectionHeader('Voice Settings'),
          const SizedBox(height: 12),

          // Speech Rate
          _buildSliderTile(
            icon: Icons.speed,
            label: 'Speech Rate',
            value: settings.speechRate,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            displayValue: '${(settings.speechRate * 100).round()}%',
            onChanged: (double v) => settings.setSpeechRate(v),
            semanticLabel: 'Speech rate ${(settings.speechRate * 100).round()} percent',
          ),
          const SizedBox(height: 8),

          // Volume
          _buildSliderTile(
            icon: Icons.volume_up,
            label: 'Volume',
            value: settings.volume,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            displayValue: '${(settings.volume * 100).round()}%',
            onChanged: (double v) => settings.setVolume(v),
            semanticLabel: 'Volume ${(settings.volume * 100).round()} percent',
          ),
          const SizedBox(height: 8),

          // Pitch
          _buildSliderTile(
            icon: Icons.music_note,
            label: 'Pitch',
            value: settings.pitch,
            min: 0.5,
            max: 2.0,
            divisions: 15,
            displayValue: settings.pitch.toStringAsFixed(1),
            onChanged: (double v) => settings.setPitch(v),
            semanticLabel: 'Pitch ${settings.pitch.toStringAsFixed(1)}',
          ),
          const SizedBox(height: 8),

          // Test TTS button
          Semantics(
            label: 'Test voice output',
            button: true,
            child: SizedBox(
              height: 72,
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.heavyImpact();
                  context.read<TtsService>().speak(
                    'This is how I will sound. Adjust the sliders above to change my voice.',
                  );
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text(
                  'Test Voice',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cardBackground,
                  foregroundColor: AppTheme.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          Semantics(
            label: 'Power read mode. Reads long text in smaller chunks.',
            toggled: settings.powerReadMode,
            child: SwitchListTile(
              value: settings.powerReadMode,
              activeThumbColor: AppTheme.accentBlue,
              title: const Text(
                'Power Read Mode',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Speaks long OCR text in small chunks for easier listening.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              onChanged: (bool value) async {
                final TtsService tts = context.read<TtsService>();
                await settings.setPowerReadMode(value);
                if (!mounted) return;
                HapticFeedback.mediumImpact();
                await tts.speak(
                  value ? 'Power read mode enabled.' : 'Power read mode disabled.',
                );
              },
              contentPadding: EdgeInsets.zero,
            ),
          ),

          const SizedBox(height: 28),

          // ── Emergency Contact ────────────────────────────────────────
          _buildSectionHeader('Emergency Contact'),
          const SizedBox(height: 12),
          Semantics(
            label: 'Emergency contact phone number',
            textField: true,
            child: TextField(
              controller: _emergencyContactController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18),
              decoration: InputDecoration(
                hintText: '+91 XXXXX XXXXX',
                filled: true,
                fillColor: AppTheme.cardBackground,
                prefixIcon: const Icon(Icons.phone, color: AppTheme.accentBlue),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save, color: AppTheme.accentBlue),
                  tooltip: 'Save emergency contact',
                  onPressed: () => _saveEmergencyContact(settings),
                ),
              ),
              onSubmitted: (_) => _saveEmergencyContact(settings),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'SOS will send an SMS with your location to this number.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textSecondary),
          ),

          const SizedBox(height: 28),

          // ── Gemini API Key ──────────────────────────────────────────
          _buildSectionHeader('Gemini AI Key'),
          const SizedBox(height: 12),
          Semantics(
            label: 'Gemini A I API key',
            textField: true,
            child: TextField(
              controller: _apiKeyController,
              obscureText: _apiKeyObscured,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Paste your Gemini API key',
                filled: true,
                fillColor: AppTheme.cardBackground,
                prefixIcon:
                    const Icon(Icons.key, color: AppTheme.accentBlue),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      icon: Icon(
                        _apiKeyObscured
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: AppTheme.textSecondary,
                      ),
                      tooltip: _apiKeyObscured ? 'Show key' : 'Hide key',
                      onPressed: () {
                        setState(() => _apiKeyObscured = !_apiKeyObscured);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.save, color: AppTheme.accentBlue),
                      tooltip: 'Save API key',
                      onPressed: () => _saveApiKey(settings),
                    ),
                  ],
                ),
              ),
              onSubmitted: (_) => _saveApiKey(settings),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            settings.hasApiKey
                ? '✓ API key saved. Scene description is enabled.'
                : 'Required for "Describe" feature. Get a key at ai.google.dev.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: settings.hasApiKey
                      ? AppTheme.success
                      : AppTheme.textSecondary,
                ),
          ),

          const SizedBox(height: 28),

          // ── OpenRouter API Key (Gemini fallback) ──────────────────
          _buildSectionHeader('OpenRouter AI Key (Gemini Fallback)'),
          const SizedBox(height: 12),
          Semantics(
            label: 'OpenRouter A I API key, used as fallback when Gemini is unavailable',
            textField: true,
            child: TextField(
              controller: _openRouterApiKeyController,
              obscureText: _openRouterApiKeyObscured,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Paste your OpenRouter API key',
                filled: true,
                fillColor: AppTheme.cardBackground,
                prefixIcon:
                    const Icon(Icons.swap_horiz, color: AppTheme.accentBlue),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      icon: Icon(
                        _openRouterApiKeyObscured
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: AppTheme.textSecondary,
                      ),
                      tooltip: _openRouterApiKeyObscured ? 'Show key' : 'Hide key',
                      onPressed: () {
                        setState(() =>
                            _openRouterApiKeyObscured = !_openRouterApiKeyObscured);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.save, color: AppTheme.accentBlue),
                      tooltip: 'Save OpenRouter key',
                      onPressed: () => _saveOpenRouterApiKey(settings),
                    ),
                  ],
                ),
              ),
              onSubmitted: (_) => _saveOpenRouterApiKey(settings),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            settings.hasOpenRouterApiKey
                ? '✓ OpenRouter key saved. Auto-fallback enabled when Gemini fails.'
                : 'Free fallback AI. Get a free key at openrouter.ai. Supports Gemini, Llama vision.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: settings.hasOpenRouterApiKey
                      ? AppTheme.success
                      : AppTheme.textSecondary,
                ),
          ),

          const SizedBox(height: 28),

          // ── Groq API Key ─────────────────────────────────────────
          _buildSectionHeader('Groq AI Key (Free Fallback)'),
          const SizedBox(height: 12),
          Semantics(
            label: 'Groq A I API key, free fast vision fallback',
            textField: true,
            child: TextField(
              controller: _groqApiKeyController,
              obscureText: _groqApiKeyObscured,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Paste your Groq API key',
                filled: true,
                fillColor: AppTheme.cardBackground,
                prefixIcon:
                    const Icon(Icons.bolt, color: AppTheme.accentBlue),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      icon: Icon(
                        _groqApiKeyObscured
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: AppTheme.textSecondary,
                      ),
                      tooltip: _groqApiKeyObscured ? 'Show key' : 'Hide key',
                      onPressed: () {
                        setState(() =>
                            _groqApiKeyObscured = !_groqApiKeyObscured);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.save, color: AppTheme.accentBlue),
                      tooltip: 'Save Groq key',
                      onPressed: () => _saveGroqApiKey(settings),
                    ),
                  ],
                ),
              ),
              onSubmitted: (_) => _saveGroqApiKey(settings),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            settings.hasGroqApiKey
                ? '✓ Groq key saved. Ultra-fast AI fallback enabled.'
                : 'Free & fast AI with vision. Get a key at console.groq.com.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: settings.hasGroqApiKey
                      ? AppTheme.success
                      : AppTheme.textSecondary,
                ),
          ),

          const SizedBox(height: 28),

          // ── Ollama Local AI Server ────────────────────────────────
          _buildSectionHeader('Ollama Local AI Server'),
          const SizedBox(height: 12),
          Semantics(
            label: 'Ollama server URL for local A I processing',
            textField: true,
            child: TextField(
              controller: _ollamaServerUrlController,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'http://192.168.1.100:11434',
                filled: true,
                fillColor: AppTheme.cardBackground,
                prefixIcon: const Icon(Icons.computer, color: AppTheme.accentBlue),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save, color: AppTheme.accentBlue),
                  tooltip: 'Save Ollama URL',
                  onPressed: () => _saveOllamaServerUrl(settings),
                ),
              ),
              onSubmitted: (_) => _saveOllamaServerUrl(settings),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            settings.hasOllamaServer
                ? '✓ Ollama server configured. Free local AI fallback active.'
                : 'Run Ollama on your PC for free offline AI. No internet needed.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: settings.hasOllamaServer
                      ? AppTheme.success
                      : AppTheme.textSecondary,
                ),
          ),

          const SizedBox(height: 28),

          // ── OpenRouteService API Key ──────────────────────────────
          _buildSectionHeader('Navigation API Key'),
          const SizedBox(height: 12),
          Semantics(
            label: 'OpenRouteService API key for walking directions',
            textField: true,
            child: TextField(
              controller: _orsApiKeyController,
              obscureText: _orsApiKeyObscured,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Paste your OpenRouteService API key',
                filled: true,
                fillColor: AppTheme.cardBackground,
                prefixIcon:
                    const Icon(Icons.navigation, color: AppTheme.accentBlue),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      icon: Icon(
                        _orsApiKeyObscured
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: AppTheme.textSecondary,
                      ),
                      tooltip: _orsApiKeyObscured ? 'Show key' : 'Hide key',
                      onPressed: () {
                        setState(() => _orsApiKeyObscured = !_orsApiKeyObscured);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.save, color: AppTheme.accentBlue),
                      tooltip: 'Save Navigation API key',
                      onPressed: () => _saveOrsApiKey(settings),
                    ),
                  ],
                ),
              ),
              onSubmitted: (_) => _saveOrsApiKey(settings),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            settings.hasOrsApiKey
                ? '✓ Navigation key saved. Walking directions enabled.'
                : 'Free key for walking directions. Get one at openrouteservice.org.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: settings.hasOrsApiKey
                      ? AppTheme.success
                      : AppTheme.textSecondary,
                ),
          ),

          const SizedBox(height: 28),

          // ── Weather API Key ─────────────────────────────────────────
          _buildSectionHeader('Weather API Key'),
          const SizedBox(height: 12),
          Semantics(
            label: 'OpenWeatherMap API key for weather alerts',
            textField: true,
            child: TextField(
              controller: _weatherApiKeyController,
              obscureText: _weatherApiKeyObscured,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Paste your OpenWeatherMap API key',
                filled: true,
                fillColor: AppTheme.cardBackground,
                prefixIcon:
                    const Icon(Icons.cloud, color: AppTheme.accentBlue),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      icon: Icon(
                        _weatherApiKeyObscured
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: AppTheme.textSecondary,
                      ),
                      tooltip: _weatherApiKeyObscured ? 'Show key' : 'Hide key',
                      onPressed: () {
                        setState(
                            () => _weatherApiKeyObscured = !_weatherApiKeyObscured);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.save, color: AppTheme.accentBlue),
                      tooltip: 'Save Weather API key',
                      onPressed: () => _saveWeatherApiKey(settings),
                    ),
                  ],
                ),
              ),
              onSubmitted: (_) => _saveWeatherApiKey(settings),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            settings.hasWeatherApiKey
                ? '✓ Weather key saved. Weather alerts enabled.'
                : 'Free key for weather updates. Get one at openweathermap.org.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: settings.hasWeatherApiKey
                      ? AppTheme.success
                      : AppTheme.textSecondary,
                ),
          ),

          const SizedBox(height: 28),

          // ── On-Device AI Models ─────────────────────────────────────
          _buildSectionHeader('On-Device AI Models'),
          const SizedBox(height: 8),
          Text(
            'Run AI entirely on your phone — no internet, no API keys, '
            'no data leaves your device.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),

          // Toggle
          Semantics(
            label: 'Use on-device A I models instead of cloud.',
            toggled: settings.useOnDeviceModels,
            child: SwitchListTile(
              value: settings.useOnDeviceModels,
              activeThumbColor: AppTheme.accentBlue,
              title: const Text(
                'Enable On-Device AI',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Use local models for scene description and assistant. '
                'Falls back to cloud if models not downloaded.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              onChanged: (bool value) async {
                final TtsService tts = context.read<TtsService>();
                await settings.setUseOnDeviceModels(value);
                if (!mounted) return;
                HapticFeedback.mediumImpact();
                await tts.speak(
                  value
                      ? 'On-device A I enabled. Models will run locally on your phone.'
                      : 'On-device A I disabled. Using cloud providers.',
                );
              },
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 12),

          // Model cards
          ...OnDeviceModel.values.map((model) => _buildModelCard(model)),

          const SizedBox(height: 40),

          // ── About ───────────────────────────────────────────────────
          _buildSectionHeader('About'),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'LumiSense v1.0.0',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'A proactive AI co-pilot for the visually impaired.\n'
                    'Built as a B.Tech CS final-year project.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppTheme.accentBlue,
            fontWeight: FontWeight.w700,
          ),
    );
  }

  Widget _buildSliderTile({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
    required String semanticLabel,
  }) {
    return Semantics(
      label: semanticLabel,
      slider: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: AppTheme.accentBlue, size: 20),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  displayValue,
                  style: const TextStyle(
                    color: AppTheme.accentBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: AppTheme.accentBlue,
              inactiveColor: AppTheme.textHint,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelCard(OnDeviceModel model) {
    final info = ModelManager.models[model]!;
    final modelMgr = context.read<ModelManager>();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  info.supportsVision ? Icons.visibility : Icons.smart_toy,
                  color: AppTheme.accentBlue,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    info.displayName,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              info.description,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Download: ~${info.estimatedTotalSizeMB}MB  •  '
              'RAM: ~${info.estimatedRamMB}MB',
              style: const TextStyle(
                  color: AppTheme.textHint, fontSize: 12),
            ),
            const SizedBox(height: 12),
            // Status + Action buttons (uses cached _modelReadyState)
            ValueListenableBuilder<double?>(
              valueListenable: modelMgr.downloadProgress[model]!,
              builder: (context, progress, _) {
                // Currently downloading
                if (progress != null) {
                  return Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: AppTheme.textHint
                              .withValues(alpha: 0.3),
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(
                                  AppTheme.accentBlue),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Downloading ${(progress * 100).toInt()}%',
                            style: const TextStyle(
                                color: AppTheme.accentBlue,
                                fontSize: 13),
                          ),
                          TextButton(
                            onPressed: () {
                              modelMgr.cancelDownload(model);
                              HapticFeedback.mediumImpact();
                            },
                            child: const Text('Cancel',
                                style: TextStyle(
                                    color: AppTheme.error)),
                          ),
                        ],
                      ),
                    ],
                  );
                }

                final isReady = _modelReadyState[model] ?? false;

                // Model ready
                if (isReady) {
                  return Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: AppTheme.success, size: 18),
                      const SizedBox(width: 6),
                      const Text('Ready',
                          style: TextStyle(
                              color: AppTheme.success,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          await modelMgr.deleteModel(model);
                          HapticFeedback.mediumImpact();
                          if (mounted) {
                            await _refreshModelReadyState();
                            context.read<TtsService>().speak(
                                '${info.displayName} deleted.');
                          }
                        },
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: AppTheme.error),
                        label: const Text('Delete',
                            style:
                                TextStyle(color: AppTheme.error)),
                      ),
                    ],
                  );
                }

                // Not downloaded
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _downloadModel(model),
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(
                        'Download (~${info.estimatedTotalSizeMB}MB)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentBlue,
                      foregroundColor: AppTheme.darkBackground,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadModel(OnDeviceModel model) async {
    final modelMgr = context.read<ModelManager>();
    final tts = context.read<TtsService>();
    final info = ModelManager.models[model]!;

    HapticFeedback.mediumImpact();
    await tts.speak(
        'Downloading ${info.displayName}. This may take a few minutes on Wi-Fi.');

    try {
      await modelMgr.downloadModel(model);
      if (mounted) {
        await _refreshModelReadyState();
        HapticFeedback.heavyImpact();
        await tts.speak('${info.displayName} downloaded and ready.');
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        await tts.speak('Download failed. Please check your internet connection and try again.');
      }
      debugPrint('Model download error: $e');
    }
  }

  Future<void> _saveEmergencyContact(SettingsProvider settings) async {
    final String value = _emergencyContactController.text.trim();

    if (value.isNotEmpty && !_isPlausiblePhoneNumber(value)) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        context.read<TtsService>().speak(
          'That does not look like a valid phone number. '
          'Please enter digits, optionally starting with a plus sign.',
        );
      }
      return;
    }

    await settings.setEmergencyContact(value);
    HapticFeedback.heavyImpact();
    if (mounted) {
      context.read<TtsService>().speak(
        value.isEmpty
            ? 'Emergency contact removed.'
            : 'Emergency contact saved.',
      );
    }
  }

  /// Returns true if [value] looks like a plausible phone number.
  /// Accepts digits, spaces, hyphens, parentheses, and an optional
  /// leading '+'. Requires at least 7 digit characters.
  static bool _isPlausiblePhoneNumber(String value) {
    final String digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.length < 7 || digitsOnly.length > 15) return false;
    // Must only contain phone-valid characters.
    return RegExp(r'^[+\d\s\-().]+$').hasMatch(value);
  }

  Future<void> _saveApiKey(SettingsProvider settings) async {
    final String value = _apiKeyController.text.trim();
    await settings.setApiKey(value);
    HapticFeedback.heavyImpact();
    if (mounted) {
      context.read<TtsService>().speak(
        value.isEmpty ? 'API key removed.' : 'API key saved. Scene description is now enabled.',
      );
    }
  }

  Future<void> _saveOpenRouterApiKey(SettingsProvider settings) async {
    final String value = _openRouterApiKeyController.text.trim();
    await settings.setOpenRouterApiKey(value);
    HapticFeedback.heavyImpact();
    if (mounted) {
      context.read<TtsService>().speak(
        value.isEmpty
            ? 'OpenRouter key removed.'
            : 'OpenRouter key saved. Auto-fallback is now active.',
      );
    }
  }

  Future<void> _saveGroqApiKey(SettingsProvider settings) async {
    final String value = _groqApiKeyController.text.trim();
    await settings.setGroqApiKey(value);
    HapticFeedback.heavyImpact();
    if (mounted) {
      context.read<TtsService>().speak(
        value.isEmpty
            ? 'Groq key removed.'
            : 'Groq key saved. Fast AI fallback is now active.',
      );
    }
  }

  Future<void> _saveOllamaServerUrl(SettingsProvider settings) async {
    final String value = _ollamaServerUrlController.text.trim();
    await settings.setOllamaServerUrl(value);
    HapticFeedback.heavyImpact();
    if (mounted) {
      context.read<TtsService>().speak(
        value.isEmpty
            ? 'Ollama server removed.'
            : 'Ollama server saved. Local AI fallback is now active.',
      );
    }
  }

  Future<void> _saveWeatherApiKey(SettingsProvider settings) async {
    final String value = _weatherApiKeyController.text.trim();
    await settings.setWeatherApiKey(value);
    HapticFeedback.heavyImpact();
    if (mounted) {
      context.read<TtsService>().speak(
        value.isEmpty
            ? 'Weather key removed.'
            : 'Weather key saved. Weather alerts are now enabled.',
      );
    }
  }

  Future<void> _saveOrsApiKey(SettingsProvider settings) async {
    final String value = _orsApiKeyController.text.trim();
    await settings.setOrsApiKey(value);
    HapticFeedback.heavyImpact();
    if (mounted) {
      context.read<TtsService>().speak(
        value.isEmpty
            ? 'Navigation key removed.'
            : 'Navigation key saved. Walking directions are now enabled.',
      );
    }
  }
}
