import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:lumisense/providers/settings_provider.dart';
import 'package:lumisense/utils/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class CaregiverDashboard extends StatefulWidget {
  const CaregiverDashboard({super.key});

  @override
  State<CaregiverDashboard> createState() => _CaregiverDashboardState();
}

class _CaregiverDashboardState extends State<CaregiverDashboard> {
  String _userName = 'User';

  @override
  void initState() {
    super.initState();
    final SharedPreferences prefs = context.read<SharedPreferences>();
    final String? storedName = prefs.getString('userName');
    if (storedName != null && storedName.trim().isNotEmpty) {
      _userName = storedName.trim();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SettingsProvider settings = context.watch<SettingsProvider>();
    final String nextCheckIn = _formatNextCheckIn();

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: AppTheme.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Caregiver Dashboard',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryYellow.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primaryYellow.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  'Caregiver mode is in prototype preview. Contact and identity are live; map and camera relay are demo visuals.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textPrimary,
                      ),
                ),
              ),

              const SizedBox(height: 16),

              // Map view
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.textHint.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      // Map placeholder (simulated map view)
                      Container(
                        width: double.infinity,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF2E7D32),
                              Color(0xFF66BB6A),
                              Color(0xFFE8F5E8),
                            ],
                          ),
                        ),
                      ),
                      
                      // User location marker
                      Positioned(
                        top: 80,
                        left: 150,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryYellow,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.darkBackground,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      
                      // Map controls
                      Positioned(
                        top: 16,
                        right: 16,
                        child: GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Opening full map view'),
                                backgroundColor: AppTheme.primaryYellow,
                              ),
                            );
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.darkBackground.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fullscreen,
                                  color: AppTheme.textPrimary,
                                  size: 16,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'View Full Map',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.textPrimary,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // User Location
              _buildInfoCard(
                title: 'User Location',
                value: 'Location shared only during SOS',
                subtitle: 'Last known location is not persisted yet',
                icon: Icons.location_on,
                hasAction: true,
                actionLabel: 'View Full Map',
                onActionTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Opening detailed location view'),
                      backgroundColor: AppTheme.primaryYellow,
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 16),
              
              // User Status
              _buildInfoCard(
                title: 'User Status',
                value: _userName,
                subtitle: settings.hasEmergencyContact
                    ? 'Emergency contact configured'
                    : 'Emergency contact missing',
                icon: Icons.person,
                statusColor: settings.hasEmergencyContact
                    ? AppTheme.online
                    : AppTheme.warning,
              ),
              
              const SizedBox(height: 16),
              
              // Upcoming Medication
              _buildInfoCard(
                title: 'Next Check-in',
                value: nextCheckIn,
                subtitle: 'Suggested caregiver follow-up reminder',
                icon: Icons.medication,
                statusColor: AppTheme.warning,
              ),
              
              const SizedBox(height: 32),
              
              // Action buttons grid
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.videocam,
                      label: 'Live Camera',
                      backgroundColor: AppTheme.primaryYellow,
                      textColor: AppTheme.darkBackground,
                      onTap: () {
                        _showCameraFeed();
                      },
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.call,
                      label: 'Call User',
                      backgroundColor: AppTheme.primaryYellow,
                      textColor: AppTheme.darkBackground,
                      onTap: () {
                        _initiateCall(settings);
                      },
                    ),
                  ),
                ],
              ),
              
              SizedBox(height: 12),
              
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.message,
                      label: 'Send Message',
                      backgroundColor: AppTheme.cardBackground,
                      textColor: AppTheme.textPrimary,
                      onTap: () {
                        _sendMessage(settings);
                      },
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.emergency,
                      label: 'Emergency SOS',
                      backgroundColor: AppTheme.error,
                      textColor: AppTheme.textPrimary,
                      onTap: () {
                        _showEmergencyDialog();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        color: AppTheme.darkBackground,
        padding: EdgeInsets.only(bottom: 16, top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Dashboard (active)
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
                    Icons.dashboard,
                    color: AppTheme.darkBackground,
                    size: 24,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Dashboard',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.primaryYellow,
                  ),
                ),
              ],
            ),
            
            // Users
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.people_outline,
                  color: AppTheme.textSecondary,
                  size: 24,
                ),
                SizedBox(height: 4),
                Text(
                  'Users',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            
            // Alerts
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.notifications_outlined,
                  color: AppTheme.textSecondary,
                  size: 24,
                ),
                SizedBox(height: 4),
                Text(
                  'Alerts',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            
            // Settings
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

  Widget _buildInfoCard({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    bool hasAction = false,
    String? actionLabel,
    VoidCallback? onActionTap,
    Color? statusColor,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: AppTheme.textSecondary,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              Spacer(),
              if (hasAction && actionLabel != null)
                GestureDetector(
                  onTap: onActionTap,
                  child: Text(
                    actionLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.primaryYellow,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            SizedBox(height: 4),
            Row(
              children: [
                if (statusColor != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 8),
                ],
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: textColor,
              size: 24,
            ),
            SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showCameraFeed() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBackground,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              'Live Camera Feed',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppTheme.textPrimary,
              ),
            ),
            SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.darkBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.videocam_off,
                        size: 64,
                        color: AppTheme.textSecondary,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Live relay is planned for a future caregiver release',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initiateCall(SettingsProvider settings) async {
    HapticFeedback.lightImpact();
    if (!settings.hasEmergencyContact) {
      _showNotice('Add emergency contact in Settings first.');
      return;
    }

    final Uri telUri = Uri(scheme: 'tel', path: settings.emergencyContact);
    if (await canLaunchUrl(telUri)) {
      await launchUrl(telUri);
      return;
    }

    _showNotice('Unable to open dialer on this device.');
  }

  Future<void> _sendMessage(SettingsProvider settings) async {
    HapticFeedback.lightImpact();
    if (!settings.hasEmergencyContact) {
      _showNotice('Add emergency contact in Settings first.');
      return;
    }

    final TextEditingController messageController = TextEditingController();
    try {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.cardBackground,
          title: Text(
            'Send Message',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppTheme.textPrimary,
            ),
          ),
          content: TextField(
            controller: messageController,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Type your message...',
              hintStyle: TextStyle(color: AppTheme.textHint),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final String text = messageController.text.trim();
                Navigator.pop(context);
                final Uri smsUri = Uri(
                  scheme: 'sms',
                  path: settings.emergencyContact,
                  queryParameters:
                      text.isEmpty ? null : <String, String>{'body': text},
                );
                if (await canLaunchUrl(smsUri)) {
                  await launchUrl(smsUri);
                } else {
                  _showNotice('Unable to open SMS app on this device.');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryYellow,
              ),
              child: Text(
                'Send',
                style: TextStyle(color: AppTheme.darkBackground),
              ),
            ),
          ],
        ),
      );
    } finally {
      messageController.dispose();
    }
  }

  void _showEmergencyDialog() {
    HapticFeedback.vibrate();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        title: Text(
          'Emergency SOS',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppTheme.error,
          ),
        ),
        content: Text(
          'This will trigger an emergency alert. Are you sure?',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Emergency SOS triggered'),
                  backgroundColor: AppTheme.error,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            child: Text(
              'Trigger SOS',
              style: TextStyle(color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  String _formatNextCheckIn() {
    final DateTime checkIn = DateTime.now().add(const Duration(hours: 1));
    final int hour = checkIn.hour == 0
        ? 12
        : (checkIn.hour > 12 ? checkIn.hour - 12 : checkIn.hour);
    final String minute = checkIn.minute.toString().padLeft(2, '0');
    final String suffix = checkIn.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  void _showNotice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.primaryYellow,
      ),
    );
  }
}