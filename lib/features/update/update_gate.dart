import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/providers.dart';
import '../../data/repositories/public_config_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/common.dart';

/// Compares the installed build number against the admin-configured
/// [appUpdateInfoProvider] gate and shows a bottom sheet nudging (or, when
/// the admin has switched Force Update on, requiring) an update. A non-forced
/// nudge only shows when this build is genuinely behind `latestBuildNumber`;
/// Force Update always shows, regardless of the build-number comparison — an
/// admin can force-lock everyone on the exact build they're already running.
/// Call [check] once, after first frame, from wherever the app already does
/// its other one-shot startup work (see app.dart's postFrameCallback).
class UpdateGate {
  UpdateGate._();

  // Re-checked on both cold start and every foreground resume (an admin can
  // flip Force Update while the app is already open) — this guards against
  // stacking a second sheet on top of one already showing.
  static bool _isShowing = false;

  /// The actual gating decision, pulled out as a pure function so the logic
  /// bug this once had (Force Update being silently unreachable whenever
  /// `installedBuild >= latestBuildNumber` — see update_gate_test.dart) can
  /// never regress unnoticed. forceUpdate is an independent "block usage
  /// right now" switch set by the admin — it must never depend on the
  /// build-number comparison. An admin needs to be able to force-lock
  /// everyone on the CURRENT build (installedBuild == latestBuildNumber, or
  /// even installedBuild higher, e.g. to force a specific in-app action
  /// before a fixed build exists yet), and that must work immediately, not
  /// only once some future build number is published. A non-forced nudge,
  /// on the other hand, only makes sense when a genuinely newer build is
  /// actually available — so it stays gated on the comparison.
  static bool shouldPrompt(AppUpdateInfo info, int installedBuild) {
    if (info.latestBuildNumber <= 0) return false;
    return info.forceUpdate || installedBuild < info.latestBuildNumber;
  }

  static Future<void> check(BuildContext context, WidgetRef ref) async {
    if (_isShowing) return;
    final info = await ref.read(appUpdateInfoProvider.future);
    if (info == null) return;

    final packageInfo = await PackageInfo.fromPlatform();
    final installedBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    if (!shouldPrompt(info, installedBuild)) return;

    if (!context.mounted || _isShowing) return;
    _isShowing = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: !info.forceUpdate,
      enableDrag: !info.forceUpdate,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => PopScope(
        canPop: !info.forceUpdate,
        child: _UpdateSheet(info: info),
      ),
    );
    _isShowing = false;
  }
}

class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet({required this.info});

  final AppUpdateInfo info;

  Future<void> _openStore() async {
    HapticFeedback.lightImpact();
    // Android always has a safe fallback (the app's own listing); iOS has no
    // equivalent constant (App Store IDs aren't guessable), so it relies on
    // the admin having set storeUrl — if they haven't, this is a no-op.
    final url = info.storeUrl.isNotEmpty
        ? info.storeUrl
        : (Platform.isAndroid
            ? 'https://play.google.com/store/apps/details?id=com.fenizotechnologies.hopprHtp'
            : '');
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSizes.xl,
        AppSizes.xl,
        AppSizes.xl,
        AppSizes.xl + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandMark(pill: true),
          const SizedBox(height: AppSizes.lg),
          Text('Update available', style: AppText.h2),
          const SizedBox(height: AppSizes.sm),
          Text(
            info.updateMessage.isNotEmpty
                ? info.updateMessage
                : 'A new version of Hoppr is available'
                    '${info.latestVersion.isNotEmpty ? ' (${info.latestVersion})' : ''}'
                    ' with performance improvements and bug fixes.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.xxl),
          AppButton(label: 'Update now', onPressed: _openStore),
          if (!info.forceUpdate) ...[
            const SizedBox(height: AppSizes.sm),
            AppButton(
              label: 'Later',
              variant: AppButtonVariant.soft,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ],
      ),
    );
  }
}
