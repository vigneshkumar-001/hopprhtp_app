import 'package:flutter/material.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../transaction/widgets/transaction_widgets.dart';
import 'dispute_status_screen.dart';

class DisputeCenterScreen extends StatefulWidget {
  const DisputeCenterScreen({super.key});

  @override
  State<DisputeCenterScreen> createState() => _DisputeCenterScreenState();
}

class _DisputeCenterScreenState extends State<DisputeCenterScreen> {
  int _selected = 0;

  static const _categories = [
    (Icons.inventory_2_outlined, 'Item Not As Described'),
    (Icons.local_shipping_outlined, 'Not Delivered'),
    (Icons.flag_outlined, 'Damaged Item'),
    (Icons.more_horiz_rounded, 'Other'),
  ];

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Dispute Center',
      bottomAction: AppButton(
        label: 'Raise Dispute',
        icon: Icons.flag_outlined,
        variant: AppButtonVariant.soft,
        onPressed: () =>
            AppNav.push(context, const DisputeStatusScreen()),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          const NoteBanner(
            icon: Icons.info_outline_rounded,
            text:
                'Having an issue? Raise a dispute before the cooling period ends. Funds stay locked while Hoppr reviews.',
          ),
          const SizedBox(height: AppSizes.xl),
          const SectionLabel('Dispute categories'),
          const SizedBox(height: AppSizes.md),
          for (int i = 0; i < _categories.length; i++) ...[
            _CategoryCard(
              icon: _categories[i].$1,
              label: _categories[i].$2,
              selected: i == _selected,
              onTap: () => setState(() => _selected = i),
            ),
            if (i != _categories.length - 1) const SizedBox(height: AppSizes.md),
          ],
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      border: Border.all(
        color: selected ? AppColors.borderStrong : AppColors.border,
        width: selected ? 1.6 : 1.2,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: AppRadii.sm,
            ),
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(child: Text(label, style: AppText.bodyStrong)),
          Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected ? AppColors.ink : AppColors.textTertiary,
            size: 22,
          ),
        ],
      ),
    );
  }
}
