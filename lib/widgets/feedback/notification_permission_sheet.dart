import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/notifications/notification_permission_prompt.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../app_button.dart';

/// The "don't miss an update" re-ask sheet — shown (per
/// [NotificationPermissionPrompt]'s cadence) to a user who already denied OS
/// notification permission. Tapping Allow re-runs the real permission
/// request and, if the OS won't show its dialog again (the common case on
/// iOS after a real denial), falls back to opening the app's Settings page
/// so there's always a working path to turning notifications back on.
Future<void> showNotificationPermissionSheet(BuildContext context) async {
  await NotificationPermissionPrompt.recordShown();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSizes.rXl)),
    ),
    builder: (_) => const _NotificationPermissionSheet(),
  );
}

class _NotificationPermissionSheet extends StatefulWidget {
  const _NotificationPermissionSheet();

  @override
  State<_NotificationPermissionSheet> createState() =>
      _NotificationPermissionSheetState();
}

class _NotificationPermissionSheetState
    extends State<_NotificationPermissionSheet> {
  bool _working = false;

  Future<void> _allow() async {
    setState(() => _working = true);
    final granted = await NotificationPermissionPrompt.requestAgain();
    if (!granted) {
      // The OS silently kept the prior denial (iOS never re-shows its
      // dialog once a decision is made; Android does the same after
      // "don't ask again") — Settings is the only remaining path.
      await openAppSettings();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.xl,
        AppSizes.lg,
        AppSizes.xl,
        AppSizes.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: AppRadii.pill,
              ),
            ),
          ),
          const SizedBox(height: AppSizes.xl),
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.lilacTile,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_active_rounded,
                color: AppColors.onLilacTile,
                size: 30,
              ),
            ),
          ).animate().scale(
            duration: 420.ms,
            curve: Curves.easeOutBack,
            begin: const Offset(0.6, 0.6),
            end: const Offset(1, 1),
          ).fadeIn(duration: 280.ms),
          const SizedBox(height: AppSizes.lg),
          Center(
            child: Text(
              "Don't miss an update",
              style: AppText.h2,
              textAlign: TextAlign.center,
            ),
          ).animate().fadeIn(delay: 120.ms, duration: 320.ms).slideY(
            begin: 0.2,
            end: 0,
            delay: 120.ms,
            duration: 320.ms,
            curve: Curves.easeOut,
          ),
          const SizedBox(height: AppSizes.sm),
          Center(
            child: Text(
              'Turn on notifications so you hear the moment a payment lands, '
              'your delivery moves, or a dispute needs your attention.',
              style: AppText.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ).animate().fadeIn(delay: 200.ms, duration: 320.ms).slideY(
            begin: 0.2,
            end: 0,
            delay: 200.ms,
            duration: 320.ms,
            curve: Curves.easeOut,
          ),
          const SizedBox(height: AppSizes.xl),
          AppButton(
                label: 'Allow notifications',
                icon: Icons.notifications_rounded,
                loading: _working,
                onPressed: _working ? null : _allow,
              )
              .animate()
              .fadeIn(delay: 300.ms, duration: 320.ms)
              .slideY(
                begin: 0.2,
                end: 0,
                delay: 300.ms,
                duration: 320.ms,
                curve: Curves.easeOut,
              ),
          const SizedBox(height: AppSizes.sm),
          Center(
            child: TextButton(
              onPressed: _working
                  ? null
                  : () => Navigator.of(context).pop(),
              child: Text(
                'Not now',
                style: AppText.bodyStrong.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ).animate().fadeIn(delay: 360.ms, duration: 320.ms),
        ],
      ),
    );
  }
}
