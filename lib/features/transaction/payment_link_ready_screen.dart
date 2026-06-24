import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import 'buyer_review_screen.dart';

/// Payment Link Ready — shown after the seller taps "Generate Payment Link".
/// Surfaces the shareable link + grand total, then lets them preview the
/// buyer's payment page. Accent (the bolt circle + Share CTA) follows the
/// selected theme: lime in the Lime theme, ink in Mono.
class PaymentLinkReadyScreen extends StatefulWidget {
  const PaymentLinkReadyScreen({super.key, required this.draft});
  final PaymentDraft draft;

  @override
  State<PaymentLinkReadyScreen> createState() => _PaymentLinkReadyScreenState();
}

class _PaymentLinkReadyScreenState extends State<PaymentLinkReadyScreen> {
  // Flips to true briefly after a copy so the link icon + Copy button can show
  // a "Copied" confirmation, then resets.
  bool _copied = false;

  String get _link => 'pay.hoppr.africa/t/${widget.draft.sellerCode}';

  void _copy() {
    Clipboard.setData(ClipboardData(text: _link));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _share() {
    Clipboard.setData(ClipboardData(text: _link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment link ready to share')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    final draft = widget.draft;
    final circle = accent.isLime ? accent.accent : AppColors.ink;
    final onCircle = accent.isLime ? accent.onAccent : AppColors.textOnDark;

    return AppScaffold(
      title: 'Payment Link Ready',
      bottomAction: AppButton(
        label: "Preview buyer's payment page",
        trailingIcon: Icons.arrow_forward_rounded,
        onPressed: () => AppNav.push(context, BuyerReviewScreen(draft: draft)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSizes.xl),
          Center(
            child: Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: circle,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: circle.withValues(alpha: 0.45),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(Icons.bolt_rounded, size: 40, color: onCircle),
            ).popIn(),
          ),
          const SizedBox(height: AppSizes.xl),
          Text('Payment link generated',
              textAlign: TextAlign.center, style: AppText.h1),
          const SizedBox(height: AppSizes.sm),
          Text(
            "Share it with the buyer. They'll see the full payment "
            'composition and the grand total before paying into escrow.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.xl),
          AppCard(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.md, vertical: AppSizes.sm),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F3EA),
                    borderRadius: AppRadii.md,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline_rounded,
                          size: 18, color: AppColors.success),
                      const SizedBox(width: AppSizes.sm),
                      Expanded(
                        child: Text(
                          _link,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSizes.sm),
                      GestureDetector(
                        onTap: _copy,
                        behavior: HitTestBehavior.opaque,
                        child: Icon(
                          _copied ? Icons.check_rounded : Icons.copy_rounded,
                          size: 18,
                          color: _copied
                              ? AppColors.success
                              : AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSizes.md),
                  child: Divider(height: 1),
                ),
                Row(
                  children: [
                    Text('Grand total payable', style: AppText.body),
                    const Spacer(),
                    Text(Money.format(draft.grandTotal), style: AppText.h3),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Share',
                  icon: Icons.ios_share_rounded,
                  accentInLime: true,
                  onPressed: _share,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: AppButton(
                  label: _copied ? 'Copied' : 'Copy',
                  icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                  variant: AppButtonVariant.soft,
                  onPressed: _copy,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
