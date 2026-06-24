import 'package:flutter/material.dart';
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
import '../onboarding/onboarding_screen.dart';
import 'edit_profile_screen.dart';
import 'identity_verification_screen.dart';
import 'payout_accounts_screen.dart';
import 'transaction_history_screen.dart';

/// Profile screen (mockup 6). Works both as a pushed route and as the embedded
/// "More" bottom-nav tab (no back button when [embedded]).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final user = state.user;

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
                          initials: user?.initials ?? 'A',
                          size: 52,
                          onDark: true,
                        ),
                        if (user?.verified ?? false)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: CircleAvatar(
                              radius: 9,
                              backgroundColor: AppAccent.of(context).accent,
                              child: Icon(Icons.check_rounded,
                                  size: 12,
                                  color: AppAccent.of(context).onAccent),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: AppSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user?.fullName ?? 'Amara Okafor',
                              style: AppText.h3
                                  .copyWith(color: AppColors.textOnDark)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                (user?.verified ?? false)
                                    ? Icons.verified_rounded
                                    : Icons.shield_outlined,
                                size: 15,
                                color: AppColors.textOnDarkMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                (user?.verified ?? false)
                                    ? 'HTP Verified'
                                    : 'Not verified',
                                style: AppText.caption.copyWith(
                                    color: AppColors.textOnDarkMuted),
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
                      value: user?.trustScore ?? 'A+',
                      label: 'Trust score',
                      valueColor: AppAccent.of(context).highlight,
                    ),
                    const CardStatDivider(),
                    CardStat(value: '${user?.deals ?? 0}', label: 'Deals'),
                    const CardStatDivider(),
                    CardStat(
                        value: '${user?.disputes ?? 0}', label: 'Disputes'),
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
                horizontal: AppSizes.sm, vertical: AppSizes.xs),
            child: Column(
              children: [
                MenuRow(
                  icon: Icons.person_outline_rounded,
                  title: 'Edit profile',
                  subtitle: 'Name, photo, contact',
                  onTap: () =>
                      AppNav.push(context, const EditProfileScreen()),
                ),
                const _RowDivider(),
                MenuRow(
                  icon: Icons.verified_outlined,
                  title: 'Identity verification',
                  subtitle: (user?.verified ?? false)
                      ? 'HTP Verified badge'
                      : 'Get the HTP Verified badge',
                  trailing: (user?.verified ?? false)
                      ? const StatusPill(
                          label: 'Verified',
                          icon: Icons.check_rounded,
                          background: AppColors.successSoft,
                          foreground: AppColors.success,
                          dense: true,
                        )
                      : null,
                  showChevron: !(user?.verified ?? false),
                  onTap: () => AppNav.push(
                      context, const IdentityVerificationScreen()),
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
                  onTap: () => _soon(context),
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
                  onTap: () => _soon(context),
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

  void _soon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Coming soon')),
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
            Text('You\'ll need your PIN or biometrics to sign back in.',
                style: AppText.body),
            const SizedBox(height: AppSizes.xl),
            AppButton(
              label: 'Log out',
              onPressed: () {
                AppScope.read(sheetCtx).signOut();
                Navigator.of(sheetCtx).pop();
                AppNav.replaceAll(context, const OnboardingScreen());
              },
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
