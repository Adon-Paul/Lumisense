import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:lumisense/providers/settings_provider.dart';
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
  bool _apiKeyObscured = true;

  @override
  void initState() {
    super.initState();
    final SettingsProvider settings = context.read<SettingsProvider>();
    _emergencyContactController =
        TextEditingController(text: settings.emergencyContact);
    _apiKeyController = TextEditingController(text: settings.apiKey);

    // Announce screen to TTS for accessibility
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<TtsService>().speak('Settings. Adjust speech, emergency contact, and A I key.');
      }
    });
  }

  @override
  void dispose() {
    _emergencyContactController.dispose();
    _apiKeyController.dispose();
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
                prefixIcon: const Icon(Icons.phone, color: AppTheme.primaryYellow),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save, color: AppTheme.primaryYellow),
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
                    const Icon(Icons.key, color: AppTheme.primaryYellow),
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
                      icon: const Icon(Icons.save, color: AppTheme.primaryYellow),
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
            color: AppTheme.primaryYellow,
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
                Icon(icon, color: AppTheme.primaryYellow, size: 20),
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
                    color: AppTheme.primaryYellow,
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
              activeColor: AppTheme.primaryYellow,
              inactiveColor: AppTheme.textHint,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveEmergencyContact(SettingsProvider settings) async {
    final String value = _emergencyContactController.text.trim();
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
}
