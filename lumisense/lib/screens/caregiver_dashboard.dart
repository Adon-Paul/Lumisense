import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:lumisense/models/history_entry.dart';
import 'package:lumisense/providers/history_provider.dart';
import 'package:lumisense/providers/settings_provider.dart';
import 'package:lumisense/services/sos_service.dart';
import 'package:lumisense/services/tts_service.dart';
import 'package:lumisense/utils/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings_screen.dart';

/// Caregiver Dashboard — allows a caregiver to monitor the user's activity,
/// location, and quickly reach them via call, SMS, or SOS.
class CaregiverDashboard extends StatefulWidget {
  const CaregiverDashboard({super.key});

  @override
  State<CaregiverDashboard> createState() => _CaregiverDashboardState();
}

class _CaregiverDashboardState extends State<CaregiverDashboard> {
  int _currentTab = 0;
  String _userName = 'User';

  // Location state
  Position? _lastPosition;
  bool _locationLoading = false;
  String? _locationError;
  DateTime? _locationUpdatedAt;

  @override
  void initState() {
    super.initState();
    final SharedPreferences prefs = context.read<SharedPreferences>();
    final String? storedName = prefs.getString('userName');
    if (storedName != null && storedName.trim().isNotEmpty) {
      _userName = storedName.trim();
    }
    _fetchLocation();
  }

  Future<void> _fetchLocation() async {
    setState(() {
      _locationLoading = true;
      _locationError = null;
    });

    final bool hasPermission = await SosService.ensureLocationPermission();
    if (!hasPermission) {
      if (mounted) {
        setState(() {
          _locationLoading = false;
          _locationError = 'Location permission not granted.';
        });
      }
      return;
    }

    final Position? position = await SosService.getCurrentPosition();
    if (!mounted) return;

    setState(() {
      _locationLoading = false;
      if (position != null) {
        _lastPosition = position;
        _locationUpdatedAt = DateTime.now();
      } else {
        _locationError = 'Could not determine location.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
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
        child: IndexedStack(
          index: _currentTab,
          children: <Widget>[
            _DashboardTab(
              userName: _userName,
              lastPosition: _lastPosition,
              locationLoading: _locationLoading,
              locationError: _locationError,
              locationUpdatedAt: _locationUpdatedAt,
              onRefreshLocation: _fetchLocation,
            ),
            const _ActivityTab(),
            const _AlertsTab(),
            _SettingsTab(userName: _userName),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    const List<_NavItem> items = <_NavItem>[
      _NavItem(icon: Icons.dashboard, label: 'Dashboard'),
      _NavItem(icon: Icons.history, label: 'Activity'),
      _NavItem(icon: Icons.notifications_outlined, label: 'Alerts'),
      _NavItem(icon: Icons.settings_outlined, label: 'Settings'),
    ];

    return Container(
      color: AppTheme.darkBackground,
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List<Widget>.generate(items.length, (int index) {
          final _NavItem item = items[index];
          final bool isActive = index == _currentTab;

          return GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              setState(() => _currentTab = index);
            },
            child: Semantics(
              label: item.label,
              button: true,
              selected: isActive,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: isActive
                        ? BoxDecoration(
                            color: AppTheme.accentBlue,
                            borderRadius: BorderRadius.circular(8),
                          )
                        : null,
                    child: Icon(
                      item.icon,
                      color: isActive
                          ? AppTheme.darkBackground
                          : AppTheme.textSecondary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isActive
                              ? AppTheme.accentBlue
                              : AppTheme.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1: Dashboard
// ═══════════════════════════════════════════════════════════════════════════════

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.userName,
    required this.lastPosition,
    required this.locationLoading,
    required this.locationError,
    required this.locationUpdatedAt,
    required this.onRefreshLocation,
  });

  final String userName;
  final Position? lastPosition;
  final bool locationLoading;
  final String? locationError;
  final DateTime? locationUpdatedAt;
  final VoidCallback onRefreshLocation;

  @override
  Widget build(BuildContext context) {
    final SettingsProvider settings = context.watch<SettingsProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ── Location card ──────────────────────────────────────────────
          _buildLocationCard(context),

          const SizedBox(height: 16),

          // ── User status ────────────────────────────────────────────────
          _buildInfoCard(
            context,
            title: 'User Status',
            value: userName,
            subtitle: settings.hasEmergencyContact
                ? 'Emergency contact configured'
                : 'Emergency contact not set',
            icon: Icons.person,
            statusColor:
                settings.hasEmergencyContact ? AppTheme.online : AppTheme.warning,
          ),

          const SizedBox(height: 16),

          // ── Recent activity summary ────────────────────────────────────
          _buildRecentActivityCard(context),

          const SizedBox(height: 32),

          // ── Action buttons ─────────────────────────────────────────────
          Row(
            children: <Widget>[
              Expanded(
                child: _ActionButton(
                  icon: Icons.call,
                  label: 'Call User',
                  backgroundColor: AppTheme.accentBlue,
                  textColor: AppTheme.darkBackground,
                  onTap: () => _initiateCall(context, settings),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: Icons.message,
                  label: 'Send SMS',
                  backgroundColor: AppTheme.accentBlue,
                  textColor: AppTheme.darkBackground,
                  onTap: () => _sendMessage(context, settings),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _ActionButton(
                  icon: Icons.map_outlined,
                  label: 'Open in Maps',
                  backgroundColor: AppTheme.cardBackground,
                  textColor: AppTheme.textPrimary,
                  onTap: () => _openInMaps(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: Icons.emergency,
                  label: 'Emergency SOS',
                  backgroundColor: AppTheme.error,
                  textColor: AppTheme.textPrimary,
                  onTap: () => _triggerSos(context, settings),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard(BuildContext context) {
    final String locationText;
    final String subtitleText;

    if (locationLoading) {
      locationText = 'Fetching location...';
      subtitleText = 'Please wait';
    } else if (lastPosition != null) {
      locationText =
          '${lastPosition!.latitude.toStringAsFixed(5)}, ${lastPosition!.longitude.toStringAsFixed(5)}';
      subtitleText = locationUpdatedAt != null
          ? 'Updated ${DateFormat('hh:mm a').format(locationUpdatedAt!)}'
          : 'Location available';
    } else {
      locationText = locationError ?? 'Location unavailable';
      subtitleText = 'Tap refresh to retry';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.location_on,
                  color: AppTheme.textSecondary, size: 20),
              const SizedBox(width: 8),
              Text(
                'User Location',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              const Spacer(),
              if (locationLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accentBlue,
                  ),
                )
              else
                GestureDetector(
                  onTap: onRefreshLocation,
                  child: const Icon(Icons.refresh,
                      color: AppTheme.accentBlue, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            locationText,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: lastPosition != null ? 16 : 14,
                ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: lastPosition != null ? AppTheme.online : AppTheme.warning,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                subtitleText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivityCard(BuildContext context) {
    final HistoryProvider history = context.watch<HistoryProvider>();
    final List<HistoryEntry> recent =
        history.entries.take(3).toList(growable: false);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.history, color: AppTheme.textSecondary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Recent Activity',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recent.isEmpty)
            Text(
              'No activity recorded yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textHint,
                  ),
            )
          else
            ...recent.map((HistoryEntry entry) {
              final DateFormat fmt = DateFormat('dd MMM, hh:mm a');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      switch (entry.type) {
                        HistoryEntryType.ocr => Icons.text_fields,
                        HistoryEntryType.objectDetection => Icons.search,
                        HistoryEntryType.sceneDescription => Icons.auto_awesome,
                      },
                      color: AppTheme.accentBlue,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            entry.title,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            entry.content,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      fmt.format(entry.createdAt),
                      style: const TextStyle(
                        color: AppTheme.textHint,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    Color? statusColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: AppTheme.textSecondary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                if (statusColor != null) ...<Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
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

  // ─── Actions ────────────────────────────────────────────────────────────

  Future<void> _initiateCall(
      BuildContext context, SettingsProvider settings) async {
    HapticFeedback.lightImpact();
    if (!settings.hasEmergencyContact) {
      _showNotice(context, 'Add emergency contact in Settings first.');
      return;
    }
    final Uri telUri = Uri(scheme: 'tel', path: settings.emergencyContact);
    if (await canLaunchUrl(telUri)) {
      await launchUrl(telUri);
    } else {
      if (context.mounted) {
        _showNotice(context, 'Unable to open dialer on this device.');
      }
    }
  }

  Future<void> _sendMessage(
      BuildContext context, SettingsProvider settings) async {
    HapticFeedback.lightImpact();
    if (!settings.hasEmergencyContact) {
      _showNotice(context, 'Add emergency contact in Settings first.');
      return;
    }

    final TextEditingController messageController = TextEditingController();
    try {
      await showDialog(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          backgroundColor: AppTheme.cardBackground,
          title: Text(
            'Send Message',
            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                  color: AppTheme.textPrimary,
                ),
          ),
          content: TextField(
            controller: messageController,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Type your message...',
              hintStyle: TextStyle(color: AppTheme.textHint),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final String text = messageController.text.trim();
                Navigator.pop(ctx);
                final Uri smsUri = Uri(
                  scheme: 'sms',
                  path: settings.emergencyContact,
                  queryParameters:
                      text.isEmpty ? null : <String, String>{'body': text},
                );
                if (await canLaunchUrl(smsUri)) {
                  await launchUrl(smsUri);
                } else {
                  if (context.mounted) {
                    _showNotice(context, 'Unable to open SMS app.');
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentBlue,
              ),
              child: const Text('Send',
                  style: TextStyle(color: AppTheme.darkBackground)),
            ),
          ],
        ),
      );
    } finally {
      messageController.dispose();
    }
  }

  void _openInMaps(BuildContext context) {
    HapticFeedback.lightImpact();
    if (lastPosition == null) {
      _showNotice(context, 'Location not available yet. Tap refresh first.');
      return;
    }
    final Uri mapsUri = Uri.parse(
      'https://maps.google.com/?q=${lastPosition!.latitude},${lastPosition!.longitude}',
    );
    launchUrl(mapsUri, mode: LaunchMode.externalApplication);
  }

  Future<void> _triggerSos(
      BuildContext context, SettingsProvider settings) async {
    HapticFeedback.vibrate();
    if (!settings.hasEmergencyContact) {
      _showNotice(context, 'Add emergency contact in Settings first.');
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        title: Text(
          'Emergency SOS',
          style: Theme.of(ctx)
              .textTheme
              .titleLarge
              ?.copyWith(color: AppTheme.error),
        ),
        content: Text(
          'This will send an emergency SMS with the user\'s location to the configured emergency contact.',
          style: Theme.of(ctx)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppTheme.textSecondary),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Send SOS',
                style: TextStyle(color: AppTheme.textPrimary)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final SosResult result =
        await SosService.sendEmergencySms(settings.emergencyContact);
    if (context.mounted) {
      _showNotice(context, result.message);
    }
  }

  void _showNotice(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.accentBlue,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 2: Activity Log
// ═══════════════════════════════════════════════════════════════════════════════

class _ActivityTab extends StatelessWidget {
  const _ActivityTab();

  @override
  Widget build(BuildContext context) {
    final HistoryProvider history = context.watch<HistoryProvider>();
    final List<HistoryEntry> entries = history.entries;

    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No activity recorded yet.\nThe user\'s OCR, identification, and scene descriptions will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final HistoryEntry entry = entries[index];
        final DateFormat fmt = DateFormat('dd MMM yyyy, hh:mm a');

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: AppStyles.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    switch (entry.type) {
                      HistoryEntryType.ocr => Icons.text_fields,
                      HistoryEntryType.objectDetection => Icons.search,
                      HistoryEntryType.sceneDescription => Icons.auto_awesome,
                    },
                    color: AppTheme.accentBlue,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    fmt.format(entry.createdAt),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                entry.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () {
                    context.read<TtsService>().speak(entry.content);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.volume_up_outlined,
                          color: AppTheme.accentBlue, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Listen',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppTheme.accentBlue,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 3: Alerts
// ═══════════════════════════════════════════════════════════════════════════════

class _AlertsTab extends StatelessWidget {
  const _AlertsTab();

  @override
  Widget build(BuildContext context) {
    final SettingsProvider settings = context.watch<SettingsProvider>();

    // Build alert list from current app state
    final List<_AlertItem> alerts = <_AlertItem>[];

    if (!settings.hasEmergencyContact) {
      alerts.add(const _AlertItem(
        severity: _AlertSeverity.high,
        title: 'Emergency contact not set',
        description:
            'The user has not configured an emergency contact. SOS will not work.',
        icon: Icons.warning_amber_rounded,
      ));
    }

    if (!settings.hasApiKey) {
      alerts.add(const _AlertItem(
        severity: _AlertSeverity.medium,
        title: 'Gemini API key missing',
        description:
            'Scene description feature is disabled. Add a key in Settings.',
        icon: Icons.key_off,
      ));
    }

    // Always show a positive status if nothing is wrong
    if (alerts.isEmpty) {
      alerts.add(const _AlertItem(
        severity: _AlertSeverity.info,
        title: 'All systems operational',
        description:
            'Emergency contact and AI features are configured and ready.',
        icon: Icons.check_circle_outline,
      ));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: alerts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final _AlertItem alert = alerts[index];
        final Color accentColor = switch (alert.severity) {
          _AlertSeverity.high => AppTheme.error,
          _AlertSeverity.medium => AppTheme.warning,
          _AlertSeverity.info => AppTheme.success,
        };

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(alert.icon, color: accentColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      alert.title,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.description,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _AlertSeverity { high, medium, info }

class _AlertItem {
  const _AlertItem({
    required this.severity,
    required this.title,
    required this.description,
    required this.icon,
  });

  final _AlertSeverity severity;
  final String title;
  final String description;
  final IconData icon;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 4: Settings (Caregiver-specific)
// ═══════════════════════════════════════════════════════════════════════════════

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.userName});

  final String userName;

  @override
  Widget build(BuildContext context) {
    final SettingsProvider settings = context.watch<SettingsProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'User Profile',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.accentBlue,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: AppStyles.cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildRow(context, 'Name', userName),
                const SizedBox(height: 8),
                _buildRow(
                  context,
                  'Emergency Contact',
                  settings.hasEmergencyContact
                      ? settings.emergencyContact
                      : 'Not set',
                ),
                const SizedBox(height: 8),
                _buildRow(
                  context,
                  'Gemini AI',
                  settings.hasApiKey ? 'Configured' : 'Not configured',
                ),
                const SizedBox(height: 8),
                _buildRow(
                  context,
                  'Speech Rate',
                  '${(settings.speechRate * 100).round()}%',
                ),
                const SizedBox(height: 8),
                _buildRow(
                  context,
                  'Power Read Mode',
                  settings.powerReadMode ? 'Enabled' : 'Disabled',
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Open full settings
          Semantics(
            label: 'Open full settings',
            button: true,
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
                icon: const Icon(Icons.settings),
                label: const Text('Open Full Settings'),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // About
          Text(
            'About',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.accentBlue,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: AppStyles.cardDecoration,
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
                  'Caregiver Dashboard\n'
                  'Monitor activity, location, and reach the user quickly.\n'
                  'Built as a B.Tech CS final-year project.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Shared: Action Button
// ═══════════════════════════════════════════════════════════════════════════════

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: textColor, size: 24),
              const SizedBox(height: 8),
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
      ),
    );
  }
}
