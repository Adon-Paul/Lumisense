import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lumisense/services/directions_service.dart';
import 'package:lumisense/utils/theme.dart';

/// Bottom panel for turn-by-turn walking navigation controls.
///
/// Three modes:
/// 1. **Input mode** — destination text field + Go button (when idle)
/// 2. **Loading mode** — progress indicator (when fetching route)
/// 3. **Active mode** — current step, progress, repeat/map/stop buttons
class DirectionsPanel extends StatefulWidget {
  const DirectionsPanel({
    super.key,
    required this.directionsService,
    required this.onNavigate,
    required this.onStop,
    required this.onOpenMap,
    required this.onRepeat,
    required this.onStatus,
  });

  final DirectionsService? directionsService;
  final ValueChanged<String> onNavigate;
  final VoidCallback onStop;
  final VoidCallback onOpenMap;
  final VoidCallback onRepeat;
  final VoidCallback onStatus;

  @override
  State<DirectionsPanel> createState() => _DirectionsPanelState();
}

class _DirectionsPanelState extends State<DirectionsPanel> {
  final TextEditingController _destController = TextEditingController();
  final FocusNode _destFocus = FocusNode();

  DirectionsService? get _ds => widget.directionsService;

  @override
  void dispose() {
    _destController.dispose();
    _destFocus.dispose();
    super.dispose();
  }

  void _onGo() {
    final String dest = _destController.text.trim();
    if (dest.isEmpty) {
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.mediumImpact();
    _destFocus.unfocus();
    widget.onNavigate(dest);
  }

  @override
  Widget build(BuildContext context) {
    final NavSessionState state = _ds?.state ?? NavSessionState.idle;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: AppTheme.accentBlue.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.textHint.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            if (state == NavSessionState.idle) _buildInputMode(),
            if (state == NavSessionState.fetchingRoute) _buildLoadingMode(),
            if (state == NavSessionState.navigating ||
                state == NavSessionState.rerouting)
              _buildActiveMode(),
            if (state == NavSessionState.arrived) _buildArrivedMode(),
          ],
        ),
      ),
    );
  }

  // ─── Input mode ─────────────────────────────────────────────────────────

  Widget _buildInputMode() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Header
        const Row(
          children: <Widget>[
            Icon(Icons.directions_walk,
                color: AppTheme.accentBlue, size: 20),
            SizedBox(width: 8),
            Text(
              'Walking Directions',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Destination input
        Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                label: 'Enter destination',
                textField: true,
                child: TextField(
                  controller: _destController,
                  focusNode: _destFocus,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Where do you want to go?',
                    prefixIcon: const Icon(Icons.place,
                        color: AppTheme.accentBlue, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    filled: true,
                    fillColor: AppTheme.darkBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                          color: AppTheme.accentBlue, width: 2),
                    ),
                  ),
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _onGo(),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Go button
            Semantics(
              label: 'Start walking directions',
              button: true,
              child: SizedBox(
                height: 52,
                width: 52,
                child: ElevatedButton(
                  onPressed: _onGo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Icon(Icons.send, size: 22),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Loading mode ───────────────────────────────────────────────────────

  Widget _buildLoadingMode() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: AppTheme.accentBlue,
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(width: 12),
          Text(
            'Finding your route...',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Active navigation mode ─────────────────────────────────────────────

  Widget _buildActiveMode() {
    final NavigationStep? step = _ds?.currentStep;
    final DirectionsResult? route = _ds?.route;
    final bool rerouting = _ds?.state == NavSessionState.rerouting;

    if (step == null || route == null) return const SizedBox.shrink();

    final int currentIdx = _ds!.currentStepIndex;
    final int totalSteps = route.steps.length;
    final double progress = totalSteps > 0 ? currentIdx / totalSteps : 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: AppTheme.textHint.withValues(alpha: 0.2),
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
          ),
        ),
        const SizedBox(height: 12),

        // Destination + step counter
        Row(
          children: <Widget>[
            Icon(
              rerouting ? Icons.refresh : Icons.directions_walk,
              color: AppTheme.accentBlue,
              size: 18,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                rerouting
                    ? 'Recalculating...'
                    : _ds?.destinationLabel ?? 'Navigating',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.accentBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${currentIdx + 1}/$totalSteps',
                style: const TextStyle(
                  color: AppTheme.accentBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Current instruction — tappable to repeat (with ripple feedback)
        Semantics(
          label: 'Current step: ${step.instruction}. Tap to hear again.',
          button: true,
          child: Material(
            color: AppTheme.darkBackground,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onRepeat();
              },
              borderRadius: BorderRadius.circular(14),
              splashColor: AppTheme.accentBlue.withValues(alpha: 0.15),
              highlightColor: AppTheme.accentBlue.withValues(alpha: 0.08),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.accentBlue.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      _stepIcon(step.type),
                      color: AppTheme.accentBlue,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            step.instruction,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            step.distanceText,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.volume_up,
                        color: AppTheme.textHint, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Action buttons row
        Row(
          children: <Widget>[
            // Repeat
            Expanded(
              child: _PanelButton(
                icon: Icons.replay,
                label: 'Repeat',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  widget.onRepeat();
                },
              ),
            ),
            const SizedBox(width: 8),

            // Status / Where am I
            Expanded(
              child: _PanelButton(
                icon: Icons.info_outline,
                label: 'Status',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  widget.onStatus();
                },
              ),
            ),
            const SizedBox(width: 8),

            // Map
            Expanded(
              child: _PanelButton(
                icon: Icons.map,
                label: 'Map',
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  widget.onOpenMap();
                },
                highlighted: true,
              ),
            ),
            const SizedBox(width: 8),

            // Stop
            Expanded(
              child: _PanelButton(
                icon: Icons.stop_circle_outlined,
                label: 'Stop',
                onPressed: () {
                  HapticFeedback.heavyImpact();
                  widget.onStop();
                },
                color: AppTheme.error,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Arrived mode ───────────────────────────────────────────────────────

  Widget _buildArrivedMode() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.flag, color: AppTheme.success, size: 36),
        const SizedBox(height: 8),
        Text(
          'Arrived at ${_ds?.destinationLabel ?? "destination"}!',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: _PanelButton(
                icon: Icons.map,
                label: 'View Map',
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  widget.onOpenMap();
                },
                highlighted: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PanelButton(
                icon: Icons.close,
                label: 'Done',
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  widget.onStop();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  IconData _stepIcon(int type) {
    switch (type) {
      case 0: return Icons.turn_left;
      case 1: return Icons.turn_right;
      case 2: return Icons.turn_sharp_left;
      case 3: return Icons.turn_sharp_right;
      case 4: return Icons.turn_slight_left;
      case 5: return Icons.turn_slight_right;
      case 6: return Icons.straight;
      case 10: return Icons.flag;
      case 11: return Icons.my_location;
      default: return Icons.directions_walk;
    }
  }
}

// ─── Panel button widget ─────────────────────────────────────────────────────

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.highlighted = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool highlighted;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color bg = highlighted
        ? AppTheme.accentBlue
        : (color ?? AppTheme.darkBackground);
    final Color fg = highlighted ? Colors.white : (color ?? AppTheme.textPrimary);

    return Semantics(
      label: label,
      button: true,
      child: SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: bg,
            foregroundColor: fg,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 20),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
