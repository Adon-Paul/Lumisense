import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lumisense/services/tts_service.dart';
import 'package:lumisense/utils/theme.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

/// Key used in SharedPreferences to track whether onboarding is complete.
const String kHasOnboarded = 'hasOnboarded';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _runSplashSequence();
  }

  Future<void> _runSplashSequence() async {
    // Speak welcome message — spec: "Splash Screen (app name + tagline spoken aloud)"
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final TtsService tts = context.read<TtsService>();
    await tts.speak('Welcome to LumiSense. Your world, in focus.');

    // Wait for TTS to finish + a brief pause
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    // Auto-navigate for returning users
    final SharedPreferences prefs = context.read<SharedPreferences>();
    final bool hasOnboarded = prefs.getBool(kHasOnboarded) ?? false;

    if (hasOnboarded) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
    // Otherwise stay on splash — user taps a button to proceed.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: <Widget>[
              const SizedBox(height: 60),

              // ── Logo + branding ───────────────────────────────────────
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Semantics(
                      label: 'LumiSense logo',
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.lightbulb_outline,
                          size: 48,
                          color: AppTheme.darkBackground,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'LumiSense',
                      style:
                          Theme.of(context).textTheme.displayLarge?.copyWith(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your world, in focus.',
                      style:
                          Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: AppTheme.textSecondary,
                                fontSize: 18,
                                fontWeight: FontWeight.w400,
                              ),
                    ),
                    const SizedBox(height: 120),
                  ],
                ),
              ),

              // ── Buttons ────────────────────────────────────────────────
              Column(
                children: <Widget>[
                  Semantics(
                    label: 'Set up LumiSense. Tap to begin first-time setup.',
                    button: true,
                    child: SizedBox(
                      width: double.infinity,
                      height: 72,
                      child: ElevatedButton(
                        onPressed: () {
                          HapticFeedback.heavyImpact();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const OnboardingScreen()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentBlue,
                          foregroundColor: AppTheme.darkBackground,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Set Up My LumiSense',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                color: AppTheme.darkBackground,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    label: 'Assist a loved one. Opens caregiver setup.',
                    button: true,
                    child: SizedBox(
                      width: double.infinity,
                      height: 72,
                      child: OutlinedButton(
                        onPressed: () {
                          HapticFeedback.heavyImpact();
                          Navigator.pushNamed(context, '/caregiver');
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.textSecondary,
                          side: const BorderSide(
                              color: AppTheme.textSecondary, width: 1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Assist a Loved One',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
