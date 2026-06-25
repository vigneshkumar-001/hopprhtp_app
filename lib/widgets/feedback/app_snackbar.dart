import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';

enum _SnackKind { success, error, warning, info }

/// The single, app-wide snackbar. Modern floating style, an icon per kind, and
/// an optional Retry action for errors. Use this instead of raw
/// `ScaffoldMessenger.showSnackBar` so feedback looks and behaves consistently.
class AppSnackbar {
  AppSnackbar._();

  static void success(BuildContext context, String message) =>
      _show(context, message, _SnackKind.success);

  static void error(BuildContext context, String message, {VoidCallback? onRetry}) =>
      _show(context, message, _SnackKind.error, onRetry: onRetry);

  static void warning(BuildContext context, String message) =>
      _show(context, message, _SnackKind.warning);

  static void info(BuildContext context, String message) =>
      _show(context, message, _SnackKind.info);

  static void _show(
    BuildContext context,
    String message,
    _SnackKind kind, {
    VoidCallback? onRetry,
  }) {
    final (IconData icon, Color accent) = switch (kind) {
      _SnackKind.success => (Icons.check_circle_rounded, AppColors.success),
      _SnackKind.error => (Icons.error_rounded, AppColors.danger),
      _SnackKind.warning => (Icons.warning_amber_rounded, AppColors.warning),
      _SnackKind.info => (Icons.info_rounded, AppColors.info),
    };
    if (kind == _SnackKind.error) HapticFeedback.heavyImpact();

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars(); // never stack — show the latest only
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        elevation: 6,
        duration: Duration(seconds: onRetry != null ? 6 : 3),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.md),
        content: Row(
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text(
                message,
                style: AppText.body.copyWith(color: AppColors.textOnDark),
              ),
            ),
          ],
        ),
        action: onRetry != null
            ? SnackBarAction(
                label: 'Retry',
                textColor: AppColors.lime,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }
}
