import 'package:flutter/material.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/models.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/segmented_control.dart' show MapBackdrop;
import 'confirm_delivery_screen.dart';
import 'widgets/transaction_widgets.dart';

/// Package on the way — live(ish) map, dispatcher card, ETA sheet.
class PackageTrackingScreen extends StatelessWidget {
  const PackageTrackingScreen({super.key, required this.draft});
  final PaymentDraft draft;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          const Positioned.fill(
              child: MapBackdrop(height: 900, animateRoute: true)),
          SafeArea(
            child: Column(
              children: [
                // Title bar — centred screen title with the back button on the
                // left (matches the standard header used elsewhere).
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSizes.md, AppSizes.sm, AppSizes.md, AppSizes.sm),
                  child: SizedBox(
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text('Package on the way', style: AppText.title),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AppIconButton(
                            icon: Icons.arrow_back_ios_new_rounded,
                            background: accent.isLime
                                ? const Color(0xFFE6E7DD)
                                : null,
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Dispatcher card spans the full width below the title.
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.screenPad),
                  child: AppCard(
                    shadow: true,
                    padding: const EdgeInsets.all(AppSizes.md),
                    child: Row(
                      children: [
                        InitialsAvatar(
                          initials: 'TB',
                          size: 38,
                          background:
                              accent.isLime ? const Color(0xFFF7EBB0) : null,
                        ),
                        const SizedBox(width: AppSizes.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Tunde Bello', style: AppText.bodyStrong),
                              const SizedBox(height: 2),
                              Text('Dispatcher · holds your code',
                                  style: AppText.caption),
                            ],
                          ),
                        ),
                        const _CallButton(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _ArrivalSheet(
              onReceive: () =>
                  AppNav.push(context, ConfirmDeliveryScreen(draft: draft)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton();
  @override
  Widget build(BuildContext context) {
    // Lime accent circle in the Lime theme; ink (black) in Mono.
    final accent = AppAccent.of(context);
    final bg = accent.isLime ? const Color(0xFFCBF24A) : AppColors.ink;
    final fg = accent.isLime ? accent.onAccent : AppColors.textOnDark;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(Icons.call_rounded, size: 18, color: fg),
    );
  }
}

class _ArrivalSheet extends StatelessWidget {
  const _ArrivalSheet({required this.onReceive});
  final VoidCallback onReceive;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppSizes.rXl),
          topRight: Radius.circular(AppSizes.rXl),
        ),
        boxShadow: [
          BoxShadow(color: AppColors.shadow, blurRadius: 24, offset: Offset(0, -6)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(AppSizes.xl, AppSizes.md, AppSizes.xl,
          AppSizes.lg + MediaQuery.of(context).padding.bottom),
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
          const SizedBox(height: AppSizes.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Estimated arrival', style: AppText.caption),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('10:00', style: AppText.h1),
                        const SizedBox(width: 6),
                        Text('Today', style: AppText.body),
                      ],
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: 'Out for delivery',
                icon: Icons.local_shipping_outlined,
                background: accent.isLime ? const Color(0xFFFBF2C6) : null,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          NoteBanner(
            icon: Icons.info_outline_rounded,
            color: accent.isLime ? const Color(0xFFEAF7C2) : null,
            textColor: accent.isLime ? const Color(0xFF181A12) : null,
            highlight: 'Tunde Bello',
            highlightColor: AppColors.textPrimary,
            text:
                'The 6-digit code was sent to Tunde Bello — not to you. Get it from them at the door.',
          ),
          const SizedBox(height: AppSizes.md),
          AppButton(
            label: 'I\'m receiving it now',
            trailingIcon: Icons.arrow_forward_rounded,
            variant: AppButtonVariant.outline,
            accentInLime: true,
            onPressed: onReceive,
          ),
        ],
      ),
    );
  }
}
