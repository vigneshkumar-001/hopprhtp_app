import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/app_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/premium_card.dart';
import '../../widgets/segmented_control.dart';
import '../../widgets/theme_reveal.dart';
import '../auth/application/auth_controller.dart';
import '../home/dashboard_stats.dart';
import 'edit_profile_screen.dart';
import 'help_support_screen.dart';
import 'identity_verification_screen.dart';
import 'payout_accounts_screen.dart';
import 'security_screen.dart';
import 'transaction_history_screen.dart';

/// Real initials from a full name — mirrors the legacy `HopprUser.initials`
/// logic so the avatar reads the same, now sourced from the live `ApiUser`.
String _initialsFor(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts[1].characters.first)
      .toUpperCase();
}

/// Real (never faked/hardcoded) 4-state identity display, driven entirely by
/// the backend's `identityStatus` — mirrors the branching in
/// [IdentityVerificationScreen].
class _IdentityDisplay {
  const _IdentityDisplay({
    required this.headline,
    required this.icon,
    required this.menuSubtitle,
    required this.pillLabel,
    required this.pillIcon,
    required this.pillBackground,
    required this.pillForeground,
  });

  final String headline; // shown next to the top-card avatar
  final IconData icon;
  final String menuSubtitle;
  final String? pillLabel; // null → no pill on the menu row
  final IconData? pillIcon;
  final Color pillBackground;
  final Color pillForeground;

  factory _IdentityDisplay.forStatus(String status) => switch (status) {
    'verified' => const _IdentityDisplay(
      headline: 'HTP Verified',
      icon: Icons.verified_rounded,
      menuSubtitle: 'HTP Verified badge',
      pillLabel: 'Verified',
      pillIcon: Icons.check_rounded,
      pillBackground: AppColors.successSoft,
      pillForeground: AppColors.success,
    ),
    'pending' => const _IdentityDisplay(
      headline: 'Verification pending',
      icon: Icons.schedule_rounded,
      menuSubtitle: 'Verification under review',
      pillLabel: 'Pending',
      pillIcon: Icons.schedule_rounded,
      pillBackground: AppColors.surfaceMuted,
      pillForeground: AppColors.textSecondary,
    ),
    'rejected' => _IdentityDisplay(
      headline: 'Verification rejected',
      icon: Icons.error_outline_rounded,
      menuSubtitle: 'Update your documents',
      pillLabel: 'Rejected',
      pillIcon: Icons.close_rounded,
      pillBackground: AppColors.danger.withValues(alpha: 0.12),
      pillForeground: AppColors.danger,
    ),
    _ => const _IdentityDisplay(
      headline: 'Not verified',
      icon: Icons.shield_outlined,
      menuSubtitle: 'Get the HTP Verified badge',
      pillLabel: null,
      pillIcon: null,
      pillBackground: AppColors.surfaceMuted,
      pillForeground: AppColors.textSecondary,
    ),
  };
}

/// Profile screen (mockup 6). Works both as a pushed route and as the embedded
/// "More" bottom-nav tab (no back button when [embedded]).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The real, live profile — never the legacy AppState snapshot (which is
    // only hydrated once at login and never refreshed during the session).
    final user = ref.watch(authControllerProvider).valueOrNull?.user;
    final verified = user?.verified ?? false;
    final identity = _IdentityDisplay.forStatus(
      user?.identityStatus ?? 'unverified',
    );
    final trustLabel = user == null
        ? 'New'
        : trustScoreLabel(deals: user.deals, trustScore: user.trustScore);

    return AppScaffold(
      title: 'Profile',
      showBack: !embedded,
      trailing: const AppIconButton(icon: Icons.more_horiz_rounded),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Stack(
                      children: [
                        InitialsAvatar(
                          initials: user != null
                              ? _initialsFor(user.fullName)
                              : '?',
                          size: 52,
                          onDark: true,
                        ),
                        if (verified)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: CircleAvatar(
                              radius: 9,
                              backgroundColor: AppAccent.of(context).accent,
                              child: Icon(
                                Icons.check_rounded,
                                size: 12,
                                color: AppAccent.of(context).onAccent,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: AppSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.fullName ?? 'Your name',
                            style: AppText.h3.copyWith(
                              color: AppColors.textOnDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                identity.icon,
                                size: 15,
                                color: AppColors.textOnDarkMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                identity.headline,
                                style: AppText.caption.copyWith(
                                  color: AppColors.textOnDarkMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    CardStat(
                      value: trustLabel,
                      label: 'Trust score',
                      valueColor: AppAccent.of(context).highlight,
                    ),
                    const CardStatDivider(),
                    CardStat(value: '${user?.deals ?? 0}', label: 'Deals'),
                    const CardStatDivider(),
                    CardStat(
                      value: '${user?.disputes ?? 0}',
                      label: 'Disputes',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          const _AppearanceToggle(),
          const SizedBox(height: AppSizes.md),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.sm,
              vertical: AppSizes.xs,
            ),
            child: Column(
              children: [
                MenuRow(
                  icon: Icons.person_outline_rounded,
                  title: 'Edit profile',
                  subtitle: 'Name, photo, contact',
                  onTap: () => AppNav.push(context, const EditProfileScreen()),
                ),
                const _RowDivider(),
                MenuRow(
                  icon: Icons.verified_outlined,
                  title: 'Identity verification',
                  subtitle: identity.menuSubtitle,
                  trailing: identity.pillLabel == null
                      ? null
                      : StatusPill(
                          label: identity.pillLabel!,
                          icon: identity.pillIcon,
                          background: identity.pillBackground,
                          foreground: identity.pillForeground,
                          dense: true,
                        ),
                  showChevron: !verified,
                  // The screen itself refetches the real status and routes
                  // to the correct view (verified/pending/rejected/start) —
                  // a single source of truth instead of duplicating the
                  // branching here.
                  onTap: () =>
                      AppNav.push(context, const IdentityVerificationScreen()),
                ),
                const _RowDivider(),
                MenuRow(
                  icon: Icons.account_balance_outlined,
                  title: 'Payout accounts',
                  subtitle: 'Where you receive funds',
                  onTap: () =>
                      AppNav.push(context, const PayoutAccountsScreen()),
                ),
                const _RowDivider(),
                MenuRow(
                  icon: Icons.shield_outlined,
                  title: 'Security & PIN',
                  subtitle: 'PIN, biometrics, devices',
                  onTap: () => AppNav.push(context, const SecurityScreen()),
                ),
                const _RowDivider(),
                MenuRow(
                  icon: Icons.show_chart_rounded,
                  title: 'Transaction history',
                  subtitle: 'All your protected deals',
                  onTap: () =>
                      AppNav.push(context, const TransactionHistoryScreen()),
                ),
                const _RowDivider(),
                MenuRow(
                  icon: Icons.info_outline_rounded,
                  title: 'Help & support',
                  subtitle: 'FAQs, contact us',
                  onTap: () => AppNav.push(context, const HelpSupportScreen()),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          AppButton(
            label: 'Log out',
            variant: AppButtonVariant.outline,
            onPressed: () => _confirmLogout(context),
          ),
          // Clearance for the floating bottom bar when shown as a tab.
          SizedBox(height: embedded ? 112 : AppSizes.lg),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.xl),
      builder: (sheetCtx) => Padding(
        // Bottom padding clears the Android system navigation bar so the
        // Cancel button is never hidden behind it.
        padding: EdgeInsets.fromLTRB(
          AppSizes.xl,
          AppSizes.xl,
          AppSizes.xl,
          AppSizes.xl + MediaQuery.of(sheetCtx).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Log out?', style: AppText.h2),
            const SizedBox(height: AppSizes.sm),
            Text(
              'You\'ll need your PIN or biometrics to sign back in.',
              style: AppText.body,
            ),
            const SizedBox(height: AppSizes.xl),
            Consumer(
              builder: (context, ref, _) => AppButton(
                label: 'Log out',
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  // Clears tokens + session; AuthGate resets to onboarding and
                  // clears the navigation stack + legacy state.
                  ref.read(authControllerProvider.notifier).logout();
                },
              ),
            ),
            const SizedBox(height: AppSizes.sm),
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.soft,
              onPressed: () => Navigator.of(sheetCtx).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.sm),
      child: Divider(height: 1),
    );
  }
}

/// Theme picker that triggers the circular [ThemeReveal] from its own position.
class _AppearanceToggle extends StatefulWidget {
  const _AppearanceToggle();

  @override
  State<_AppearanceToggle> createState() => _AppearanceToggleState();
}

class _AppearanceToggleState extends State<_AppearanceToggle> {
  void _onChanged(int i) {
    final value = i == 1;
    final state = AppScope.read(context);
    void apply() => state.setLimeTheme(value);

    final reveal = ThemeReveal.maybeOf(context);
    if (reveal != null) {
      reveal.play(apply: apply); // smooth cross-dissolve into the new theme
    } else {
      apply();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_outlined, size: 18),
              const SizedBox(width: AppSizes.sm),
              Text('Appearance', style: AppText.bodyStrong),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          SegmentedControl(
            segments: const ['Default', 'Lime'],
            selected: state.limeTheme ? 1 : 0,
            onChanged: _onChanged,
          ),
        ],
      ),
    );
  }
}
