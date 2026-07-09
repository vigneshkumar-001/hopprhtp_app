import 'package:flutter/material.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/segmented_control.dart' show LabeledBar;
import '../transaction/widgets/transaction_widgets.dart';
import 'dispute_status_screen.dart';

/// AI Evidence Review — admin-facing, Hoppr Vision first-pass assessment.
class AiEvidenceReviewScreen extends StatelessWidget {
  const AiEvidenceReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'AI Evidence Review',
      trailing: const StatusPill(label: 'ADMIN', dense: true),
      bottomAction: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'Open admin decision',
            icon: Icons.swap_horiz_rounded,
            onPressed: () => AppNav.push(context, const DisputeStatusScreen()),
          ),
          const SizedBox(height: AppSizes.sm),
          AppButton(
            label: 'Request missing evidence',
            icon: Icons.chat_bubble_outline_rounded,
            variant: AppButtonVariant.soft,
            onPressed: () =>
                AppSnackbar.success(context, 'Evidence request sent to seller'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 16),
              const SizedBox(width: 6),
              Text('Hoppr Vision', style: AppText.bodyStrong),
              const SizedBox(width: 6),
              Text('First-layer automated assessment', style: AppText.caption),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          const NoteBanner(
            icon: Icons.info_outline_rounded,
            text:
                'Advisory only. Hoppr Vision flags issues to assist the administrator. It never decides settlement — final outcome stays under manual review.',
          ),
          const SizedBox(height: AppSizes.md),
          ItemSummaryCard(
            product: 'MacBook Pro M2',
            subtitle: 'Case #DSP-4471 · HTP-LGS-8881',
            amount: 0,
            trailing: const StatusPill(
              label: 'Not as described',
              icon: Icons.flag_outlined,
              foreground: AppColors.danger,
              dense: true,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              children: const [
                LabeledBar(label: 'Evidence completeness', value: 0.78),
                SizedBox(height: AppSizes.lg),
                LabeledBar(
                  label: 'Fraud-risk score',
                  value: 0.41,
                  color: AppColors.danger,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.auto_awesome_rounded, size: 16),
                    SizedBox(width: 6),
                    Text('Evidence summary', style: AppText.bodyStrong),
                  ],
                ),
                const SizedBox(height: AppSizes.sm),
                Text(
                  'Delivery was confirmed via OTP, but the device\'s GPS position at confirmation sits 1.2 km outside the buyer\'s geofence. The waybill weight (2.1 kg) is consistent with the declared item. Seller has not uploaded a counter-evidence photo. Two signals warrant a closer look before settlement.',
                  style: AppText.body,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardSectionLabel('Evidence processed'),
                const SizedBox(height: AppSizes.md),
                _EvidenceRow(
                  icon: Icons.description_outlined,
                  label: 'Transaction metadata',
                  present: true,
                ),
                const SizedBox(height: AppSizes.md),
                _EvidenceRow(
                  icon: Icons.image_outlined,
                  label: 'Seller counter-evidence photo',
                  present: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({
    required this.icon,
    required this.label,
    required this.present,
  });

  final IconData icon;
  final String label;
  final bool present;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: AppSizes.sm),
        Expanded(child: Text(label, style: AppText.bodyStrong)),
        Row(
          children: [
            Icon(
              present ? Icons.check_rounded : Icons.close_rounded,
              size: 15,
              color: present ? AppColors.success : AppColors.danger,
            ),
            const SizedBox(width: 4),
            Text(
              present ? 'Present' : 'Missing',
              style: AppText.caption.copyWith(
                color: present ? AppColors.success : AppColors.danger,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
