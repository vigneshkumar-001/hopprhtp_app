import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/dto/transaction_dto.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/state_views.dart';
import '../dispute/dispute_center_screen.dart';
import '../settlement/seller_settlement_screen.dart';
import 'application/transactions_provider.dart';
import 'settlement_ledger_screen.dart';
import 'widgets/transaction_widgets.dart';

/// Cooling Period — real countdown from the backend's `coolingEndsAt` (Phase
/// 5). No hardcoded duration: missing data or a non-cooling status shows a
/// clear message instead of a fake timer.
class CoolingPeriodScreen extends ConsumerStatefulWidget {
  const CoolingPeriodScreen({super.key, this.transactionId});

  /// Real backend transaction id. Left nullable (rather than required) only
  /// so the one pre-existing demo call site (`DeliveryConfirmedScreen`'s
  /// legacy "View Transaction" flow) keeps compiling unchanged — it shows the
  /// safe fallback below instead of real data.
  final String? transactionId;

  @override
  ConsumerState<CoolingPeriodScreen> createState() =>
      _CoolingPeriodScreenState();
}

class _CoolingPeriodScreenState extends ConsumerState<CoolingPeriodScreen> {
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Repaints the countdown every second only while there's an actual live
  /// countdown to show — the value is always recomputed from the real
  /// coolingEndsAt on each tick, this timer only forces the redraw. Viewing
  /// an already-completed/disputed/older transaction costs zero timer ticks.
  void _ensureTicker(bool active) {
    if (active) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.transactionId;
    if (id == null) {
      return const AppScaffold(
        title: 'Cooling Period',
        body: ErrorRetryView(
          message:
              'Transaction reference is missing. Please go back and try again.',
        ),
      );
    }

    final txAsync = ref.watch(transactionDetailProvider(id));
    // Only used to decide whether to show the seller-only settlement link —
    // reuses the existing tracking snapshot rather than a new fetch/field.
    final isSeller = ref
        .watch(trackingProvider(id))
        .maybeWhen(data: (t) => t.isSeller, orElse: () => false);

    void refresh() {
      ref.invalidate(transactionDetailProvider(id));
      ref.invalidate(trackingProvider(id));
    }

    return AppScaffold(
      title: 'Cooling Period',
      scrollable: true,
      body: AsyncValueView(
        value: txAsync,
        onRetry: refresh,
        data: (tx) {
          final endsAt = tx.coolingEndsAt;
          final counting =
              tx.status == ApiTxStatus.cooling &&
              endsAt != null &&
              endsAt.isAfter(DateTime.now());
          _ensureTicker(counting);
          return _CoolingBody(tx: tx, isSeller: isSeller, onRefresh: refresh);
        },
      ),
    );
  }
}

class _CoolingBody extends StatelessWidget {
  const _CoolingBody({
    required this.tx,
    required this.isSeller,
    required this.onRefresh,
  });
  final ApiTransaction tx;
  final bool isSeller;
  final VoidCallback onRefresh;

  /// Derived from the real audit timeline — not a separate/fake field.
  DateTime? get _coolingStart {
    for (final e in tx.timeline) {
      if (e.event == 'cooling_started' && e.at != null) return e.at;
    }
    for (final e in tx.timeline) {
      if (e.event == 'delivered' && e.at != null) return e.at;
    }
    return null;
  }

  bool get _isPastEnd {
    final endsAt = tx.coolingEndsAt;
    return endsAt != null && !endsAt.isAfter(DateTime.now());
  }

  bool get _isCountingDown => tx.status == ApiTxStatus.cooling && !_isPastEnd;

  String get _settlementStatusLabel => switch (tx.status) {
    ApiTxStatus.cooling => _isPastEnd ? 'Pending release' : 'In cooling',
    ApiTxStatus.released || ApiTxStatus.completed => 'Released',
    ApiTxStatus.disputed => 'On hold (disputed)',
    ApiTxStatus.cancelled ||
    ApiTxStatus.refunded ||
    ApiTxStatus.returned ||
    ApiTxStatus.undeliverable => 'Not applicable',
    _ => 'Not yet started',
  };

  String get _statusMessage => switch (tx.status) {
    ApiTxStatus.disputed =>
      'This order is under dispute review. Payout is on hold until it is resolved.',
    ApiTxStatus.released || ApiTxStatus.completed =>
      'Cooling period completed. Payout has been released to the seller.',
    ApiTxStatus.cancelled ||
    ApiTxStatus.refunded ||
    ApiTxStatus.returned ||
    ApiTxStatus.undeliverable => 'This transaction is no longer active.',
    // Reached only once time is already up — see _isCountingDown above.
    ApiTxStatus.cooling =>
      'Cooling period completed. Seller payout is now eligible if there is no active dispute.',
    _ => 'This transaction has not entered its cooling period yet.',
  };

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    final endsAt = tx.coolingEndsAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSizes.sm),
        AppCard(
          color: accent.isLime
              ? const Color(0xFFD3E8F9)
              : AppColors.surfaceMuted,
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            children: [
              StatusPill(label: tx.status.label, dense: true),
              const SizedBox(height: AppSizes.md),
              if (endsAt == null)
                Text(
                  'Cooling period details are not available yet.',
                  textAlign: TextAlign.center,
                  style: AppText.body,
                )
              else if (_isCountingDown)
                _Countdown(remaining: endsAt.difference(DateTime.now()))
              else
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: AppText.h3,
                ),
              if (endsAt != null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSizes.lg),
                  child: Divider(height: 1),
                ),
                Text('Cooling ends', style: AppText.caption),
                const SizedBox(height: 4),
                Text(Dates.medium(endsAt), style: AppText.h3),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardSectionLabel('Details'),
              const SizedBox(height: AppSizes.md),
              _DetailRow(
                label: 'Delivery confirmed',
                value: _coolingStart != null
                    ? Dates.relative(_coolingStart!)
                    : 'Not available',
              ),
              const SizedBox(height: AppSizes.sm),
              _DetailRow(
                label: 'Escrow amount',
                value: Money.format(tx.itemSubtotalNaira),
              ),
              const SizedBox(height: AppSizes.sm),
              _DetailRow(
                label: 'Settlement status',
                value: _settlementStatusLabel,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Why Cooling Period?', style: AppText.h3),
              const SizedBox(height: AppSizes.sm),
              Text(
                'The buyer can raise a dispute during the cooling period. Seller payout unlocks after this period if no dispute is raised.',
                style: AppText.body,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        AppButton(
          label: 'Refresh',
          icon: Icons.refresh_rounded,
          variant: AppButtonVariant.outline,
          onPressed: onRefresh,
        ),
        const SizedBox(height: AppSizes.md),
        AppButton(
          label: 'View Settlement Ledger',
          trailingIcon: Icons.arrow_forward_rounded,
          onPressed: () => AppNav.push(
            context,
            SettlementLedgerScreen(transactionId: tx.id),
          ),
        ),
        if (isSeller) ...[
          const SizedBox(height: AppSizes.md),
          AppButton(
            label: 'View Seller Settlement',
            icon: Icons.account_balance_outlined,
            variant: AppButtonVariant.outline,
            onPressed: () => AppNav.push(
              context,
              SellerSettlementScreen(transactionId: tx.id),
            ),
          ),
        ],
        if (tx.status == ApiTxStatus.cooling) ...[
          const SizedBox(height: AppSizes.md),
          GestureDetector(
            onTap: () =>
                AppNav.push(context, DisputeCenterScreen(transactionId: tx.id)),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.flag_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Raise a dispute before it ends',
                    style: AppText.bodyStrong,
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSizes.lg),
      ],
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.remaining});
  final Duration remaining;

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final d = remaining.isNegative ? Duration.zero : remaining;
    final h = _two(d.inHours);
    final m = _two(d.inMinutes.remainder(60));
    final s = _two(d.inSeconds.remainder(60));
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TimeBlock(value: h, label: 'Hours'),
        const _Colon(),
        _TimeBlock(value: m, label: 'Minutes'),
        const _Colon(),
        _TimeBlock(value: s, label: 'Seconds'),
      ],
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppText.display.copyWith(fontSize: 40, height: 1)),
        const SizedBox(height: 4),
        Text(label, style: AppText.caption),
      ],
    );
  }
}

class _Colon extends StatelessWidget {
  const _Colon();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
      child: Text(
        ':',
        style: AppText.display.copyWith(fontSize: 36, height: 1),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: AppText.caption)),
        Text(value, style: AppText.bodyStrong),
      ],
    );
  }
}
