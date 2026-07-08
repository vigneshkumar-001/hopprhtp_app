import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/dto/transaction_ledger_dto.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/state_views.dart';
import '../dispute/dispute_center_screen.dart';
import '../settlement/seller_settlement_screen.dart';
import 'application/transactions_provider.dart';
import 'widgets/transaction_widgets.dart';

/// Settlement & Resolution Ledger — real backend data (Phase 6). Every amount
/// and every feed row comes from `GET /transactions/:id/ledger`; nothing here
/// is fabricated client-side.
class SettlementLedgerScreen extends ConsumerWidget {
  const SettlementLedgerScreen({super.key, this.transactionId});

  /// Real backend transaction id. Left nullable so the one pre-existing call
  /// site (`CoolingPeriodScreen`'s "View Details" button, now updated to pass
  /// a real id) and any other stale caller keep compiling safely.
  final String? transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = transactionId;
    if (id == null) {
      return const AppScaffold(
        title: 'Settlement & Resolution Ledger',
        body: ErrorRetryView(
          message:
              'Transaction reference is missing. Please go back and try again.',
        ),
      );
    }

    final ledgerAsync = ref.watch(transactionLedgerProvider(id));

    return AppScaffold(
      title: 'Settlement & Resolution Ledger',
      scrollable: true,
      bottomAction: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'View seller settlement',
            icon: Icons.account_balance_outlined,
            onPressed: () =>
                AppNav.push(context, SellerSettlementScreen(transactionId: id)),
          ),
          const SizedBox(height: AppSizes.sm),
          AppButton(
            label: 'Open Dispute Center',
            icon: Icons.flag_outlined,
            variant: AppButtonVariant.soft,
            onPressed: () =>
                AppNav.push(context, DisputeCenterScreen(transactionId: id)),
          ),
        ],
      ),
      body: AsyncValueView(
        value: ledgerAsync,
        onRetry: () => ref.invalidate(transactionLedgerProvider(id)),
        data: (ledger) => _LedgerBody(
          ledger: ledger,
          onRefresh: () => ref.invalidate(transactionLedgerProvider(id)),
        ),
      ),
    );
  }
}

class _LedgerBody extends StatelessWidget {
  const _LedgerBody({required this.ledger, required this.onRefresh});
  final TransactionLedger ledger;
  final VoidCallback onRefresh;

  (Color, Color) _statusColors(String status) {
    final s = status.toLowerCase();
    if (s.contains('released')) {
      return (AppColors.successSoft, AppColors.success);
    }
    if (s.contains('hold') || s.contains('disputed')) {
      return (AppColors.surfaceMuted, AppColors.warning);
    }
    if (s.contains('refund') || s.contains('cancel')) {
      return (AppColors.surfaceMuted, AppColors.danger);
    }
    return (AppColors.surfaceMuted, AppColors.textPrimary);
  }

  @override
  Widget build(BuildContext context) {
    final (escrowBg, escrowFg) = _statusColors(ledger.escrowStatus);
    final (settleBg, settleFg) = _statusColors(ledger.settlementStatus);
    final cooling = ledger.coolingPeriod;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSizes.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: CardSectionLabel('Escrow summary')),
                  StatusPill(
                    label: ledger.escrowStatus,
                    dense: true,
                    background: escrowBg,
                    foreground: escrowFg,
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.md),
              SummaryRow(
                label: 'Escrow amount',
                value: Money.format(ledger.escrowAmountNaira),
              ),
              const SizedBox(height: AppSizes.sm),
              SummaryRow(
                label: 'Platform fee',
                value: Money.format(ledger.platformFeeNaira),
                badge: const StatusPill(
                  label: 'retained',
                  dense: true,
                  background: AppColors.surfaceMuted,
                  foreground: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSizes.sm),
              SummaryRow(
                label: 'Seller payout',
                value: Money.format(ledger.sellerPayoutNaira),
              ),
              if (ledger.refundAmountNaira != null) ...[
                const SizedBox(height: AppSizes.sm),
                SummaryRow(
                  label: 'Refund amount',
                  value: Money.format(ledger.refundAmountNaira!),
                ),
              ],
              const SizedBox(height: AppSizes.md),
              Row(
                children: [
                  Text('Settlement status', style: AppText.caption),
                  const SizedBox(width: AppSizes.sm),
                  StatusPill(
                    label: ledger.settlementStatus,
                    dense: true,
                    background: settleBg,
                    foreground: settleFg,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (cooling != null) ...[
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardSectionLabel('Cooling period'),
                const SizedBox(height: AppSizes.md),
                SummaryRow(
                  label: 'Started',
                  value: cooling.startedAt != null
                      ? Dates.relative(cooling.startedAt!)
                      : 'Not available',
                ),
                const SizedBox(height: AppSizes.sm),
                SummaryRow(
                  label: 'Ends',
                  value: cooling.endsAt != null
                      ? Dates.medium(cooling.endsAt!)
                      : 'Not available',
                ),
                const SizedBox(height: AppSizes.sm),
                SummaryRow(label: 'Status', value: cooling.status),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSizes.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: CardSectionLabel('Ledger feed')),
                  AppIconButton(icon: Icons.refresh_rounded, onTap: onRefresh),
                ],
              ),
              const SizedBox(height: AppSizes.md),
              if (ledger.ledger.isEmpty)
                Text(
                  'No settlement ledger records are available yet.',
                  style: AppText.body.copyWith(color: AppColors.textTertiary),
                )
              else
                for (int i = 0; i < ledger.ledger.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSizes.md),
                  _LedgerRow(item: ledger.ledger[i]),
                ],
            ],
          ),
        ),
        const SizedBox(height: AppSizes.lg),
      ],
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.item});
  final LedgerFeedItem item;

  @override
  Widget build(BuildContext context) {
    final amount = item.amountNaira;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFFEDEDEE),
            shape: BoxShape.circle,
          ),
          child: Icon(
            item.isMonetary ? Icons.payments_outlined : Icons.check_rounded,
            size: 14,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: AppText.bodyStrong.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (item.remarks != null && item.remarks!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(item.remarks!, style: AppText.caption),
              ],
              const SizedBox(height: 2),
              Text(Dates.relative(item.timestamp), style: AppText.caption),
            ],
          ),
        ),
        if (amount != null)
          Text(
            Money.format(amount.abs()),
            style: AppText.caption.copyWith(
              color: amount < 0 ? AppColors.danger : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
      ],
    );
  }
}
