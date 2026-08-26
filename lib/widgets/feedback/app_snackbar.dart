import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/connectivity.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';

enum _SnackKind { success, error, warning, info }

/// True exactly when [next] represents "just came back online" relative to
/// [previous] — i.e. a genuine offline→online transition, not "was already
/// online" or "still offline". A free top-level function (not inlined into
/// the listener callback) specifically so this decision — the one thing
/// standing between a helpful auto-retry and a silently-resubmitted wrong
/// PIN — is unit-testable on its own, with plain [AsyncValue] instances and
/// no widget, SnackBar, or stream involved at all.
@visibleForTesting
bool isReconnectTransition(AsyncValue<bool>? previous, AsyncValue<bool> next) {
  final wasOffline = previous?.valueOrNull == false;
  final isOnlineNow = next.valueOrNull == true;
  return wasOffline && isOnlineNow;
}

/// The single, app-wide snackbar. Modern floating style, an icon per kind, and
/// an optional Retry action for errors. Use this instead of raw
/// `ScaffoldMessenger.showSnackBar` so feedback looks and behaves consistently.
class AppSnackbar {
  AppSnackbar._();

  static void success(BuildContext context, String message) =>
      _show(context, message, _SnackKind.success);

  /// [autoRetryOnReconnect] fires [onRetry] itself the instant the device
  /// comes back online, instead of leaving the person to notice their
  /// connection returned and tap Retry themselves — the way a modern app is
  /// expected to recover. Only pass `true` when the failure this snackbar is
  /// reporting was actually caused by connectivity (see
  /// [ApiException.isConnectionIssue]) — auto-firing [onRetry] for, say, a
  /// wrong PIN the moment WiFi reconnects would silently resubmit a doomed
  /// attempt the person never asked to retry.
  static void error(
    BuildContext context,
    String message, {
    VoidCallback? onRetry,
    bool autoRetryOnReconnect = false,
  }) {
    final controller = _show(context, message, _SnackKind.error, onRetry: onRetry);
    if (autoRetryOnReconnect && onRetry != null && controller != null) {
      _retryOnReconnect(context, onRetry, controller);
    }
  }

  static void warning(BuildContext context, String message) =>
      _show(context, message, _SnackKind.warning);

  static void info(BuildContext context, String message) =>
      _show(context, message, _SnackKind.info);

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _show(
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
    return messenger.showSnackBar(
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

  /// Watches connectivity for exactly one offline→online transition and
  /// fires [onRetry] when it happens. Stops listening the moment the
  /// snackbar itself goes away for any other reason first (the person
  /// tapped Retry manually, it timed out, or a newer snackbar replaced it)
  /// — a stale listener must never fire a retry for an error the person
  /// already left behind.
  static void _retryOnReconnect(
    BuildContext context,
    VoidCallback onRetry,
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason> controller,
  ) {
    final container = ProviderScope.containerOf(context, listen: false);
    var fired = false;
    late final ProviderSubscription<AsyncValue<bool>> subscription;
    subscription = container.listen<AsyncValue<bool>>(connectivityProvider, (
      previous,
      next,
    ) {
      if (fired || !isReconnectTransition(previous, next)) return;
      fired = true;
      subscription.close();
      controller.close();
      onRetry();
    });
    controller.closed.then((_) {
      if (!fired) subscription.close();
    });
  }
}
