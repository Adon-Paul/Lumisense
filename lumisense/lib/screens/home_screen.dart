import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:lumisense/providers/settings_provider.dart';
import 'package:lumisense/services/sos_service.dart';
import 'package:lumisense/services/tts_service.dart';
import 'package:lumisense/utils/theme.dart';
import 'camera_screen.dart';
import 'caregiver_dashboard.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Announce screen to visually impaired users
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<TtsService>().speak(
          'Home screen. Tap the large button to describe your surroundings, '
          'or use the quick buttons below.',
        );
      }
    });
  }

  void _openCameraLiveView() {
    HapticFeedback.heavyImpact();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
  }

  Future<void> _onSosTap() async {
    HapticFeedback.heavyImpact();
    final TtsService tts = context.read<TtsService>();
    final SettingsProvider settings = context.read<SettingsProvider>();

    if (!settings.hasEmergencyContact) {
      await tts.speak('No emergency contact set. Please add one in Settings.');
      return;
    }

    await tts.speak('Sending emergency message.');
    final SosResult result =
        await SosService.sendEmergencySms(settings.emergencyContact);
    if (mounted) {
      await tts.speak(result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: <Widget>[
                  ExcludeSemantics(
                    child: Icon(Icons.lightbulb_outline,
                        color: AppTheme.primaryYellow, size: 24),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'LumiSense',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  // Settings gear
                  Semantics(
                    label: 'Settings',
                    button: true,
                    child: IconButton(
                      icon: const Icon(Icons.settings,
                          color: AppTheme.textSecondary),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ── Main content ────────────────────────────────────────────
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      // ── Large action button ───────────────────────────
                      Semantics(
                        label:
                            'Describe my surroundings. Opens camera for AI scene description.',
                        button: true,
                        child: GestureDetector(
                          onTap: _openCameraLiveView,
                          child: Container(
                            width: 280,
                            height: 280,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryYellow,
                              shape: BoxShape.circle,
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: AppTheme.primaryYellow
                                      .withValues(alpha: 0.3),
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                const Icon(Icons.remove_red_eye_outlined,
                                    size: 64,
                                    color: AppTheme.darkBackground),
                                const SizedBox(height: 16),
                                Text(
                                  'Describe My\nSurroundings',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        color: AppTheme.darkBackground,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                        height: 1.2,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),

                      // ── Quick access buttons ──────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          _buildQuickButton(
                            icon: Icons.text_fields,
                            label: 'Read Text',
                            onTap: _openCameraLiveView,
                          ),
                          _buildQuickButton(
                            icon: Icons.search,
                            label: 'Find Objects',
                            onTap: _openCameraLiveView,
                          ),
                          _buildQuickButton(
                            icon: Icons.sos,
                            label: 'SOS',
                            onTap: _onSosTap,
                            color: AppTheme.error,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

      // ── Bottom navigation ─────────────────────────────────────────────
      bottomNavigationBar: Container(
        color: AppTheme.darkBackground,
        padding: const EdgeInsets.only(bottom: 16, top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            _buildNavItem(
              icon: Icons.home,
              label: 'Home',
              isActive: true,
              onTap: () {},
            ),
            _buildNavItem(
              icon: Icons.history,
              label: 'History',
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const HistoryScreen()));
              },
            ),
            _buildNavItem(
              icon: Icons.people_outline,
              label: 'Caregiver',
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CaregiverDashboard()));
              },
            ),
            _buildNavItem(
              icon: Icons.settings,
              label: 'Settings',
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SettingsScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Quick button with 72dp touch target ───────────────────────────────

  Widget _buildQuickButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final Color fg = color ?? AppTheme.textPrimary;

    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.heavyImpact();
          onTap();
        },
        child: SizedBox(
          width: 80,
          height: 80,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: (color ?? AppTheme.textHint).withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(icon, color: fg, size: 24),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(color: fg, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Bottom nav item ──────────────────────────────────────────────────

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    final Color color =
        isActive ? AppTheme.primaryYellow : AppTheme.textSecondary;

    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: isActive
                  ? BoxDecoration(
                      color: AppTheme.primaryYellow,
                      borderRadius: BorderRadius.circular(8),
                    )
                  : null,
              child: Icon(icon,
                  color:
                      isActive ? AppTheme.darkBackground : AppTheme.textSecondary,
                  size: 24),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
