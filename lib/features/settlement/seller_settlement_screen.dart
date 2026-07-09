import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/dto/tracking_dto.dart';
import '../../data/dto/transaction_ledger_dto.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/state_views.dart';
import '../auth/application/auth_controller.dart';
import '../transaction/application/transactions_provider.dart';
import '../transaction/widgets/transaction_widgets.dart';
import '../wallet/wallet_screen.dart';

/// Seller Settlement — real backend data (Phase 7). Payout amount, cooling
/// window, and eligibility all come from the transaction ledger + tracking
/// endpoints; "Release Payout" calls the existing, already-hardened
/// `POST /transactions/:id/release` (seller-only, cooling-time gated, atomic
/// duplicate-prevention claim — see transaction.service.ts). Nothing here
/// computes a final wallet balance; that stays entirely backend-owned.
class SellerSettlementScreen extends ConsumerStatefulWidget {
  const SellerSettlementScreen({super.key, this.transactionId});

  /// Real backend transaction id. Left nullable so the one pre-existing call
  /// site (`SettlementLedgerScreen`'s "View seller settlement" button, now
  /// updated to pass a real id) keeps compiling safely if ever reached without one.
  final String? transactionId;

  @override
  ConsumerState<SellerSettlementScreen> createState() =>
      _SellerSettlementScreenState();
}

class _SellerSettlementScreenState
    extends ConsumerState<SellerSettlementScreen> {
  bool _releasing = false;

  Future<bool> _confirmRelease() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadii.xl),
        title: Text('Release payout?', style: AppText.h3),
        content: Text(
          'Release payout to your wallet? This cannot be undone.',
          style: AppText.body,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSizes.md,
          0,
          AppSizes.md,
          AppSizes.md,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: AppText.bodyStrong.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Release',
              style: AppText.bodyStrong.copyWith(color: AppColors.success),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _releasePayout(String id) async {
    if (_releasing) return;
    final confirmed = await _confirmRelease();
    if (!confirmed || !mounted) return;

    setState(() => _releasing = true);
    try {
      await ref.read(transactionRepositoryProvider).release(id);
      if (!mounted) return;
      AppSnackbar.success(context, 'Payout released to your wallet.');
      // Real state changed everywhere — refresh every provider that could be
      // showing stale data now. Backend remains the sole source of truth for
      // the actual wallet balance; nothing here adds to it locally.
      ref.invalidate(transactionDetailProvider(id));
      ref.invalidate(transactionsProvider);
      ref.invalidate(transactionLedgerProvider(id));
      ref.invalidate(trackingProvider(id));
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(walletLedgerProvider);
      // A clean release bumps the seller's real trust score/deals count on
      // the backend — refresh the profile so Home/Profile's dashboard stats
      // pick it up without a full app restart. Best-effort only.
      try {
        await ref.read(authControllerProvider.notifier).refreshProfile();
      } catch (_) {
        // Non-critical — stats just keep showing the last known value.
      }
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.userMessage);
      // A timeout/network error here doesn't mean the release didn't happen
      // server-side — refresh so a retry is checked against real, current
      // eligibility rather than the cached pre-attempt ledger snapshot.
      ref.invalidate(transactionLedgerProvider(id));
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(
          context,
          'Could not release payout. Please try again.',
        );
      }
      ref.invalidate(transactionLedgerProvider(id));
    } finally {
      if (mounted) setState(() => _releasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.transactionId;
    if (id == null) {
      return const AppScaffold(
        title: 'Seller Settlement',
        body: ErrorRetryView(
          message:
              'Transaction reference is missing. Please go back and try again.',
        ),
      );
    }

    final trackingAsync = ref.watch(trackingProvider(id));
    final ledgerAsync = ref.watch(transactionLedgerProvider(id));

    void retry() {
      ref.invalidate(trackingProvider(id));
      ref.invalidate(transactionLedgerProvider(id));
    }

    // A fetch failure goes to the shared snackbar, never an inline page
    // block — fires once per new error, not on every rebuild.
    ref.listen(trackingProvider(id), (previous, next) {
      final err = next.error;
      if (err != null) {
        AppSnackbar.error(context, friendlyError(err), onRetry: retry);
      }
    });
    ref.listen(transactionLedgerProvider(id), (previous, next) {
      final err = next.error;
      if (err != null) {
        AppSnackbar.error(context, friendlyError(err), onRetry: retry);
      }
    });

    return AppScaffold(
      title: 'Seller Settlement',
      body: trackingAsync.when(
        loading: () => const _LoadingBody(),
        error: (_, _) => const SizedBox.shrink(),
        data: (tracking) => ledgerAsync.when(
          loading: () => const _LoadingBody(),
          error: (_, _) => const SizedBox.shrink(),
          data: (ledger) => _SettlementBody(
            transactionId: id,
            tracking: tracking,
            ledger: ledger,
            releasing: _releasing,
            onRelease: () => _releasePayout(id),
          ),
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 320,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _SettlementBody extends StatelessWidget {
  const _SettlementBody({
    required this.transactionId,
    required this.tracking,
    required this.ledger,
    required this.releasing,
    required this.onRelease,
  });

  final String transactionId;
  final TransactionTracking tracking;
  final TransactionLedger ledger;
  final bool releasing;
  final VoidCallback onRelease;

  static const _blockedStatuses = {
    'disputed',
    'cancelled',
    'refunded',
    'returned',
    'undeliverable',
    'released',
    'completed',
  };

  bool get _isReleased =>
      ledger.status == 'released' || ledger.status == 'completed';

  bool get _coolingTimeUp {
    final endsAt = ledger.coolingPeriod?.endsAt;
    return endsAt != null && !endsAt.isAfter(DateTime.now());
  }

  bool get _canRelease {
    if (!tracking.isSeller) return false;
    if (_blockedStatuses.contains(ledger.status)) return false;
    if (ledger.status != 'cooling') return false;
    return _coolingTimeUp;
  }

  String get _eligibilityMessage {
    if (_isReleased) return 'Payout already released.';
    if (ledger.status == 'disputed') return 'Payout is on hold due to dispute.';
    if (ledger.status == 'cancelled' ||
        ledger.status == 'refunded' ||
        ledger.status == 'returned' ||
        ledger.status == 'undeliverable') {
      return 'This transaction is no longer eligible for payout.';
    }
    if (ledger.status == 'cooling') {
      final endsAt = ledger.coolingPeriod?.endsAt;
      if (endsAt == null) {
        return 'Cooling period details are not available yet.';
      }
      if (!_coolingTimeUp) return 'Payout unlocks after cooling period ends.';
      return 'Payout is ready to release.';
    }
    return 'This transaction has not reached cooling yet.';
  }

  DateTime? get _releasedAt {
    for (final item in ledger.ledger) {
      if (item.type == 'lifecycle' && item.title == 'Funds released') {
        return item.timestamp;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final reference =
        '#${transactionId.substring(transactionId.length - 6).toUpperCase()}';
    final cooling = ledger.coolingPeriod;
    final releasedAt = _releasedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSizes.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Transaction', style: AppText.caption),
                        const SizedBox(height: 2),
                        Text(reference, style: AppText.h3),
                      ],
                    ),
                  ),
                  StatusPill(label: ledger.settlementStatus, dense: true),
                ],
              ),
              const SizedBox(height: AppSizes.md),
              if (_isReleased) ...[
                Center(
                  child: AnimatedMoney(
                    ledger.sellerPayoutNaira,
                    style: AppText.display.copyWith(fontSize: 34),
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
                if (releasedAt != null)
                  Center(
                    child: Text(
                      'Released ${Dates.relative(releasedAt)}',
                      style: AppText.caption,
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSizes.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardSectionLabel('Payout breakdown'),
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSizes.md),
                child: Divider(height: 1),
              ),
              SummaryRow(
                label: _isReleased ? 'Released to you' : 'Seller payout',
                value: Money.format(ledger.sellerPayoutNaira),
                emphasized: true,
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
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSizes.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardSectionLabel('Payout eligibility'),
              const SizedBox(height: AppSizes.sm),
              Text(_eligibilityMessage, style: AppText.body),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        if (tracking.isSeller)
          AppButton(
            label: 'Release Payout',
            trailingIcon: Icons.arrow_forward_rounded,
            enabled: _canRelease && !releasing,
            loading: releasing,
            onPressed: onRelease,
          ),
        const SizedBox(height: AppSizes.md),
        AppButton(
          label: 'View in wallet',
          icon: Icons.account_balance_wallet_outlined,
          variant: AppButtonVariant.outline,
          onPressed: () => AppNav.push(context, const WalletScreen()),
        ),
        const SizedBox(height: AppSizes.lg),
      ],
    );
  }
}
