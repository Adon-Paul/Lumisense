import 'package:flutter/material.dart';
import 'package:lumisense/utils/theme.dart';
import 'caregiver_dashboard.dart';
import 'camera_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final bool _isVoiceCommandsActive = true;

  void _openCameraLiveView() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CameraScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Status bar
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  // Connection status
                  Icon(
                    Icons.wifi,
                    color: AppTheme.success,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'SYSTEM CONNECTED',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.success,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Spacer(),
                  // Battery indicator
                  Icon(
                    Icons.battery_5_bar,
                    color: AppTheme.textPrimary,
                    size: 16,
                  ),
                  SizedBox(width: 4),
                  Text(
                    '85%',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            
            // Main content area
            Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Main action button
                      GestureDetector(
                        onTap: _openCameraLiveView,
                        child: Container(
                          width: 280,
                          height: 280,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryYellow,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryYellow.withValues(alpha: 0.3),
                                blurRadius: 20,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.remove_red_eye_outlined,
                                size: 64,
                                color: AppTheme.darkBackground,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Describe My\nSurroundings',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                      
                      SizedBox(height: 60),
                      
                      // Quick access buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
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
                            icon: Icons.navigation,
                            label: 'Navigate',
                            onTap: _openCameraLiveView,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Voice commands indicator
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.mic,
                    color: _isVoiceCommandsActive ? AppTheme.primaryYellow : AppTheme.textSecondary,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Voice Commands Active',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: _isVoiceCommandsActive ? AppTheme.primaryYellow : AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        color: AppTheme.darkBackground,
        padding: EdgeInsets.only(bottom: 16, top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Home icon (active)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryYellow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.home,
                    color: AppTheme.darkBackground,
                    size: 24,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Home',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.primaryYellow,
                  ),
                ),
              ],
            ),
            
            // Caregiver icon (inactive)
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CaregiverDashboard(),
                  ),
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_outline,
                    color: AppTheme.textSecondary,
                    size: 24,
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Caregiver',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            
            // Settings icon (inactive)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.settings_outlined,
                  color: AppTheme.textSecondary,
                  size: 24,
                ),
                SizedBox(height: 4),
                Text(
                  'Settings',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.textHint.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                color: AppTheme.textPrimary,
                size: 24,
              ),
            ),
            SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}