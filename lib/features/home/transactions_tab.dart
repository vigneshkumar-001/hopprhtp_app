import 'package:flutter/material.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/app_state.dart';
import '../../data/models/models.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_card.dart';
import '../../widgets/transaction_card.dart';
import '../transaction/transaction_detail_screen.dart';

/// Reusable list tab (used for Initiation & Transit in the bottom nav).
class TransactionsTab extends StatelessWidget {
  const TransactionsTab({
    super.key,
    required this.title,
    required this.subtitle,
    required this.stage,
    this.statusFilter,
  });

  final String title;
  final String subtitle;
  final TxStage stage;
  final TxStatus? statusFilter;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    var list = state.byStage(stage);
    if (statusFilter != null) {
      list = list.where((t) => t.status == statusFilter).toList();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(
              AppSizes.screenPad, AppSizes.lg, AppSizes.screenPad, 112),
          children: [
            Text(title, style: AppText.h1),
            const SizedBox(height: 4),
            Text(subtitle, style: AppText.body),
            const SizedBox(height: AppSizes.xl),
            if (list.isEmpty)
              AppCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.lg, vertical: AppSizes.xxxl),
                child: Column(
                  children: [
                    const Icon(Icons.inbox_outlined,
                        size: 40, color: AppColors.textTertiary),
                    const SizedBox(height: AppSizes.md),
                    Text('Nothing here yet', style: AppText.bodyStrong),
                    const SizedBox(height: 4),
                    Text('New deals will appear in this list.',
                        style: AppText.caption),
                  ],
                ),
              )
            else
              ...list
                  .asMap()
                  .entries
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSizes.md),
                        child: TransactionCard(
                          tx: e.value,
                          colorIndex: e.key,
                          onTap: () => AppNav.push(
                              context, TransactionDetailScreen(tx: e.value)),
                        ),
                      ))
                  .toList()
                  .staggerEnter(),
          ],
        ),
      ),
    );
  }
}
