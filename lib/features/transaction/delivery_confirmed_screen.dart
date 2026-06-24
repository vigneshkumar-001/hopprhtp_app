import 'package:flutter/material.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/app_state.dart';
import '../../data/models/models.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import 'cooling_period_screen.dart';

/// Delivery Confirmed — fee released, item value enters cooling.
class DeliveryConfirmedScreen extends StatelessWidget {
  const DeliveryConfirmedScreen({super.key, required this.draft});
  final PaymentDraft draft;

  @override
  Widget build(BuildContext context) {
    // Record a real transaction so it shows up on Home/Wallet afterwards.
    final accent = AppAccent.of(context);
    return AppScaffold(
      showBack: false,
      title: '',
      bottomAction: AppButton(
        label: 'View Transaction',
        trailingIcon: Icons.arrow_forward_rounded,
        onPressed: () {
          AppScope.read(context).addTransaction(
            EscrowTransaction(
              id: 'cool-${DateTime.now().microsecondsSinceEpoch}',
              code: draft.sellerCode,
              merchantName: draft.sellerName,
              productName: draft.productName,
              amount: draft.itemSubtotal,
              stage: TxStage.cooling,
              status: TxStatus.delivered,
            ),
          );
          AppNav.push(context, const CoolingPeriodScreen());
        },
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSizes.sm),
          const _AnimatedDotStrip(count: 16),
          const SizedBox(height: AppSizes.xxl),
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                  color: accent.isLime
                      ? const Color(0xFF1F8A5B)
                      : AppColors.ink,
                  shape: BoxShape.circle),
              child: const Icon(Icons.verified_user_rounded,
                  color: AppColors.textOnDark, size: 36),
            ).popIn(),
          ),
          const SizedBox(height: AppSizes.xl),
          Text('Delivery Confirmed!',
              textAlign: TextAlign.center, style: AppText.h1),
          const SizedBox(height: AppSizes.sm),
          Text('Transaction status updated successfully.',
              textAlign: TextAlign.center, style: AppText.body),
          const SizedBox(height: AppSizes.xl),
          const _StepRow(
            icon: Icons.local_shipping_outlined,
            text: 'Delivery fee released to dispatcher',
          ),
          const SizedBox(height: AppSizes.md),
          const _StepRow(
            icon: Icons.schedule_rounded,
            text: 'Item value moved to Cooling Period',
          ),
          const SizedBox(height: AppSizes.md),
          const _StepRow(
            icon: Icons.account_balance_outlined,
            text: 'Seller settlement subject to cooling period',
          ),
        ],
      ),
    );
  }
}

/// Celebratory strip of dots with a soft "scan" wave travelling across it.
class _AnimatedDotStrip extends StatefulWidget {
  const _AnimatedDotStrip({this.count = 16});
  final int count;

  @override
  State<_AnimatedDotStrip> createState() => _AnimatedDotStripState();
}

class _AnimatedDotStripState extends State<_AnimatedDotStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fixed height so the growing dots never relayout (shake) the screen.
    return SizedBox(
      height: 16,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // Wave centre travels off both edges so the loop is seamless.
          final wave = _c.value * (widget.count + 6) - 3;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(widget.count, (i) {
              final dist = (i - wave).abs();
              final t = (1 - dist / 3.0).clamp(0.0, 1.0);
              return Container(
                width: 5,
                height: 8 + 8 * t,
                decoration: BoxDecoration(
                  color: Color.lerp(AppColors.border, AppColors.ink, t * t),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
                color: AppColors.surfaceMuted, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, size: 16),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(child: Text(text, style: AppText.bodyStrong)),
          Icon(icon, size: 18, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}
