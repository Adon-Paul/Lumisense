import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lumisense/providers/settings_provider.dart';
import 'package:lumisense/screens/splash_screen.dart' show kHasOnboarded;
import 'package:lumisense/services/tts_service.dart';
import 'package:lumisense/utils/theme.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill from existing settings if re-entering
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final SettingsProvider settings = context.read<SettingsProvider>();
      _emergencyContactController.text = settings.emergencyContact;
      _apiKeyController.text = settings.apiKey;
      context.read<TtsService>().speak(
        'Welcome. Enter your name and emergency contact to get started.',
      );
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emergencyContactController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    if (!_formKey.currentState!.validate()) return;

    HapticFeedback.heavyImpact();

    // Persist settings
    final SettingsProvider settings = context.read<SettingsProvider>();
    final SharedPreferences prefs = context.read<SharedPreferences>();

    final String emergencyContact = _emergencyContactController.text.trim();
    final String apiKey = _apiKeyController.text.trim();
    final String userName = _nameController.text.trim();

    // Save emergency contact + API key
    if (emergencyContact.isNotEmpty) {
      await settings.setEmergencyContact(emergencyContact);
    }
    if (apiKey.isNotEmpty) {
      await settings.setApiKey(apiKey);
    }

    // Persist user name and onboarding flag
    await prefs.setString('userName', userName);
    await prefs.setBool(kHasOnboarded, true);

    if (!mounted) return;

    await context.read<TtsService>().speak('Setup complete. Welcome, $userName.');

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBackground,
        elevation: 0,
        leading: Semantics(
          label: 'Go back',
          button: true,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.pop(context);
            },
          ),
        ),
        title: Text(
          'LumiSense Setup',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: <Widget>[
                const SizedBox(height: 16),

                Text(
                  'Welcome to\nLumiSense',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Let\'s set up your profile and emergency details.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.5,
                      ),
                ),
                const SizedBox(height: 36),

                // ── Name ─────────────────────────────────────────────────
                _buildFieldLabel('Your Name'),
                const SizedBox(height: 8),
                Semantics(
                  label: 'Name input',
                  textField: true,
                  child: TextFormField(
                    controller: _nameController,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Enter your name',
                      filled: true,
                      fillColor: AppTheme.cardBackground,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your name';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 24),

                // ── Emergency contact ────────────────────────────────────
                _buildFieldLabel('Emergency Contact Number'),
                const SizedBox(height: 8),
                Semantics(
                  label: 'Emergency contact phone number',
                  textField: true,
                  child: TextFormField(
                    controller: _emergencyContactController,
                    keyboardType: TextInputType.phone,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      hintText: '+91 XXXXX XXXXX',
                      filled: true,
                      fillColor: AppTheme.cardBackground,
                      prefixIcon:
                          Icon(Icons.phone, color: AppTheme.primaryYellow),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Used for SOS. You can change this later in Settings.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 24),

                // ── Gemini API key (optional) ────────────────────────────
                _buildFieldLabel('Gemini AI Key (optional)'),
                const SizedBox(height: 8),
                Semantics(
                  label: 'Gemini A I API key',
                  textField: true,
                  child: TextFormField(
                    controller: _apiKeyController,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Paste your Gemini API key',
                      filled: true,
                      fillColor: AppTheme.cardBackground,
                      prefixIcon:
                          Icon(Icons.key, color: AppTheme.primaryYellow),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Required for the "Describe Scene" feature. Get a free key at ai.google.dev.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 48),

                // ── Continue button ──────────────────────────────────────
                Semantics(
                  label: 'Continue to LumiSense',
                  button: true,
                  child: SizedBox(
                    width: double.infinity,
                    height: 72,
                    child: ElevatedButton(
                      onPressed: _handleContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryYellow,
                        foregroundColor: AppTheme.darkBackground,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Continue',
                        style:
                            Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: AppTheme.darkBackground,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppTheme.primaryYellow,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}
