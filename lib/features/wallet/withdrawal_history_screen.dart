import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/error_messages.dart';
import '../../core/network/socket_service.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/formatters.dart';
import '../../data/dto/wallet_dto.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/blur_sheet.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_loaders.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/state_views.dart';

/// Every status filter chip, in display order — deliberately excludes
/// "Cancelled" (rare, and not one of the actionable states an admin drives
/// this list through) to match the chip row this was scoped to.
const _kStatusChips = <(String, String?)>[
  ('All', null),
  ('Pending', 'pending'),
  ('Under Review', 'under_review'),
  ('Approved', 'approved'),
  ('Processing', 'processing'),
  ('Paid', 'paid'),
  ('Rejected', 'rejected'),
  ('Failed', 'failed'),
];

/// Full withdrawal (payout request) history — every request this user has
/// ever made, backed by the same `GET /wallet/withdrawals` the Wallet
/// screen's "latest 3" section already uses (see [walletWithdrawalsProvider]).
/// Filtering/searching is client-side over that single already-fetched list
/// (a user's own withdrawal count is always small — no pagination needed).
class WithdrawalHistoryScreen extends ConsumerStatefulWidget {
  const WithdrawalHistoryScreen({super.key, this.openWithdrawalId});

  /// Set when opened from a push-notification tap for a specific withdrawal
  /// (see app.dart) — the detail sheet opens automatically once the list has
  /// loaded and the id is found, rather than trying to deep-link before real
  /// data exists.
  final String? openWithdrawalId;

  @override
  ConsumerState<WithdrawalHistoryScreen> createState() =>
      _WithdrawalHistoryScreenState();
}

class _WithdrawalHistoryScreenState
    extends ConsumerState<WithdrawalHistoryScreen>
    with WidgetsBindingObserver {
  String? _statusFilter;
  String _query = '';
  bool _openedInitial = false;

  StreamSubscription<WithdrawalSocketEvent>? _socketSub;
  Timer? _reloadDebounce;
  late final SocketService _socket;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _socket = ref.read(socketServiceProvider);
    _socketSub = _socket.withdrawalEvents.listen((event) {
      AppLogger.debug(
        '[socket] withdrawal history reload scheduled: '
        'withdrawal=${event.withdrawalId} status=${event.status}',
      );
      _scheduleReload();
      if (mounted) AppSnackbar.info(context, 'Withdrawal status updated');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _socketSub?.cancel();
    _reloadDebounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(walletWithdrawalsProvider);
    // autoDispose + watch means invalidate() alone re-fetches lazily on next
    // build; awaiting the provider's future here is what makes this usable
    // as a RefreshIndicator callback (it needs a Future to know when to stop
    // spinning) and as the resume/socket refetch.
    await ref.read(walletWithdrawalsProvider.future);
  }

  void _maybeOpenInitial(List<WithdrawalRequest> requests) {
    if (_openedInitial || widget.openWithdrawalId == null) return;
    _openedInitial = true;
    WithdrawalRequest? match;
    for (final r in requests) {
      if (r.id == widget.openWithdrawalId) {
        match = r;
        break;
      }
    }
    final found = match;
    if (found != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showWithdrawalDetailSheet(context, found);
      });
    }
  }

  List<WithdrawalRequest> _filtered(List<WithdrawalRequest> all) {
    final q = _query.trim().toLowerCase();
    return all.where((r) {
      if (_statusFilter != null && r.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      return r.bankName.toLowerCase().contains(q) ||
          Money.format(r.amountNaira).toLowerCase().contains(q) ||
          r.shortId.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(walletWithdrawalsProvider);
    ref.listen(walletWithdrawalsProvider, (previous, next) {
      final err = next.error;
      if (err != null) {
        AppSnackbar.error(
          context,
          friendlyError(err),
          onRetry: () => ref.invalidate(walletWithdrawalsProvider),
        );
      }
      final data = next.valueOrNull;
      if (data != null) _maybeOpenInitial(data);
    });

    return AppScaffold(
      title: 'Withdrawal History',
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          _SearchField(
            value: _query,
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: AppSizes.md),
          _statusChips(),
          const SizedBox(height: AppSizes.md),
          Expanded(
            child: async.when(
              loading: () => const Center(child: AppCircularLoader()),
              error: (_, _) => const SizedBox.shrink(),
              data: (all) {
                _maybeOpenInitial(all);
                final requests = _filtered(all);
                if (all.isEmpty) {
                  return const EmptyStateView(
                    icon: Icons.receipt_long_outlined,
                    title: 'No withdrawal requests yet.',
                    subtitle:
                        'When you request a withdrawal, it will appear here.',
                  );
                }
                if (requests.isEmpty) {
                  return const EmptyStateView(
                    icon: Icons.search_off_rounded,
                    title: 'No matching withdrawals',
                    subtitle: 'Try a different filter or search term.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  color: AppColors.ink,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: AppSizes.xxl),
                    itemCount: requests.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSizes.sm),
                    itemBuilder: (context, i) => AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSizes.lg,
                        vertical: AppSizes.xs,
                      ),
                      child: WithdrawalHistoryRow(request: requests[i]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChips() {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _kStatusChips.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSizes.sm),
        itemBuilder: (context, i) {
          final (label, value) = _kStatusChips[i];
          final selected = _statusFilter == value;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _statusFilter = value);
            },
            child: AnimatedContainer(
              duration: AppDurations.fast,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.md,
                vertical: AppSizes.sm,
              ),
              decoration: BoxDecoration(
                color: selected ? AppColors.ink : AppColors.surfaceMuted,
                borderRadius: AppRadii.pill,
              ),
              child: Text(
                label,
                style: AppText.label.copyWith(
                  color: selected
                      ? AppColors.textOnDark
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadii.md,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.search_rounded,
            size: 19,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: AppText.body,
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search by bank or amount',
              ),
            ),
          ),
          if (value.isNotEmpty)
            GestureDetector(
              onTap: () => onChanged(''),
              behavior: HitTestBehavior.opaque,
              child: const Icon(
                Icons.close_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

/// One row shared by the Wallet screen's "latest 3" section and this full
/// history list — tapping opens [showWithdrawalDetailSheet].
class WithdrawalHistoryRow extends StatelessWidget {
  const WithdrawalHistoryRow({super.key, required this.request});
  final WithdrawalRequest request;

  @override
  Widget build(BuildContext context) {
    final style = withdrawalStatusStyle(request.status);
    final dateLabel = request.updatedAt != null
        ? 'Updated ${Dates.relative(request.updatedAt!)}'
        : request.requestedAt != null
        ? 'Requested ${Dates.relative(request.requestedAt!)}'
        : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadii.sm,
        onTap: () => showWithdrawalDetailSheet(context, request),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      Money.format(request.amountNaira),
                      style: AppText.bodyStrong,
                    ),
                  ),
                  StatusPill(
                    label: style.label,
                    background: style.background,
                    foreground: style.foreground,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '${request.bankName} · ${request.payoutAccountMasked}'
                '${dateLabel != null ? ' · $dateLabel' : ''}',
                style: AppText.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                withdrawalStatusMessage(request),
                style: AppText.caption.copyWith(
                  color:
                      request.isRejected || request.isFailed
                      ? AppColors.danger
                      : AppColors.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WithdrawalStatusStyle {
  const WithdrawalStatusStyle({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;
}

/// Per-status pill colours — real backend status only, never re-derived or
/// guessed.
WithdrawalStatusStyle withdrawalStatusStyle(String status) => switch (status) {
  'pending' => WithdrawalStatusStyle(
    label: 'Pending',
    background: AppColors.warning.withValues(alpha: 0.14),
    foreground: AppColors.warning,
  ),
  'under_review' => WithdrawalStatusStyle(
    label: 'Under Review',
    background: AppColors.info.withValues(alpha: 0.14),
    foreground: AppColors.info,
  ),
  'approved' => WithdrawalStatusStyle(
    label: 'Approved',
    background: AppColors.successSoft,
    foreground: AppColors.success,
  ),
  'processing' => WithdrawalStatusStyle(
    label: 'Processing',
    background: AppColors.info.withValues(alpha: 0.14),
    foreground: AppColors.info,
  ),
  'paid' => WithdrawalStatusStyle(
    label: 'Paid',
    background: AppColors.successSoft,
    foreground: AppColors.success,
  ),
  'rejected' => WithdrawalStatusStyle(
    label: 'Rejected',
    background: AppColors.danger.withValues(alpha: 0.12),
    foreground: AppColors.danger,
  ),
  'failed' => WithdrawalStatusStyle(
    label: 'Failed',
    background: AppColors.danger.withValues(alpha: 0.12),
    foreground: AppColors.danger,
  ),
  'cancelled' => WithdrawalStatusStyle(
    label: 'Cancelled',
    background: AppColors.surfaceMuted,
    foreground: AppColors.textSecondary,
  ),
  _ => WithdrawalStatusStyle(
    label: status,
    background: AppColors.surfaceMuted,
    foreground: AppColors.textSecondary,
  ),
};

/// Plain-language, per-status preview line — folds the rejection/failure
/// reason straight into the message (e.g. "Rejected: payout account
/// mismatch") instead of a separate line, so a single glance explains what
/// happened.
String withdrawalStatusMessage(WithdrawalRequest r) => switch (r.status) {
  'pending' => 'Waiting for admin review',
  'under_review' => 'Admin is reviewing your request',
  'approved' => 'Approved — your payout will be sent shortly',
  'processing' => 'Your withdrawal is being processed for payout',
  'paid' => 'Paid to ${r.payoutAccountMasked}',
  'rejected' => r.rejectionReason != null
      ? 'Rejected: ${r.rejectionReason}'
      : 'Your withdrawal request was rejected',
  'failed' => r.failureReason != null
      ? 'Failed: ${r.failureReason}'
      : 'Your withdrawal could not be completed',
  'cancelled' => 'This withdrawal request was cancelled',
  _ => '',
};

/// "12 May 2025, 4:30 PM" — full date + time, for the detail sheet's
/// Requested/Last updated/timeline rows.
String _dateTimeLabel(DateTime? d) =>
    d == null ? 'Not available' : '${Dates.medium(d)}, ${Dates.time(d)}';

class _TimelineStep {
  const _TimelineStep(this.label, this.at, {this.negative = false});
  final String label;
  final DateTime? at;
  final bool negative;
}

List<_TimelineStep> _timelineFor(WithdrawalRequest r) {
  if (r.status == 'cancelled') {
    return [
      _TimelineStep('Requested', r.requestedAt),
      _TimelineStep('Cancelled', r.cancelledAt, negative: true),
    ];
  }
  final steps = [
    _TimelineStep('Requested', r.requestedAt),
    _TimelineStep('Under Review', r.reviewedAt),
    _TimelineStep('Approved', r.approvedAt),
    _TimelineStep('Processing', r.processingAt),
  ];
  if (r.status == 'rejected') {
    steps.add(_TimelineStep('Rejected', r.rejectedAt, negative: true));
  } else if (r.status == 'failed') {
    steps.add(_TimelineStep('Failed', r.failedAt, negative: true));
  } else {
    steps.add(_TimelineStep('Paid', r.paidAt));
  }
  return steps;
}

/// Opens the shared Withdrawal Details bottom sheet for [request] — used by
/// both the Wallet screen's "latest 3" section and [WithdrawalHistoryScreen].
void showWithdrawalDetailSheet(BuildContext context, WithdrawalRequest request) {
  showBlurredSheet(
    context,
    builder: (ctx) => _WithdrawalDetailSheet(request: request),
  );
}

class _WithdrawalDetailSheet extends StatelessWidget {
  const _WithdrawalDetailSheet({required this.request});
  final WithdrawalRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final style = withdrawalStatusStyle(r.status);
    final reason = r.status == 'rejected'
        ? r.rejectionReason
        : r.status == 'failed'
        ? r.failureReason
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.xl,
        AppSizes.md,
        AppSizes.xl,
        AppSizes.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Withdrawal', style: AppText.h2),
                    const SizedBox(height: 2),
                    Text('#${r.shortId}', style: AppText.caption),
                  ],
                ),
              ),
              StatusPill(
                label: style.label,
                background: style.background,
                foreground: style.foreground,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Text(Money.format(r.amountNaira), style: AppText.h1),
          const SizedBox(height: AppSizes.lg),
          _DetailRow(
            icon: Icons.schedule_rounded,
            label: 'Requested',
            value: _dateTimeLabel(r.requestedAt),
          ),
          _DetailRow(
            icon: Icons.update_rounded,
            label: 'Last updated',
            value: _dateTimeLabel(r.updatedAt),
          ),
          _DetailRow(
            icon: Icons.payments_outlined,
            label: 'Payout method',
            value: r.payoutMethodLabel,
          ),
          _DetailRow(
            icon: Icons.account_balance_outlined,
            label: 'Bank name',
            value: r.bankName,
          ),
          _DetailRow(
            icon: Icons.credit_card_outlined,
            label: 'Account number',
            value: r.payoutAccountMasked,
          ),
          if (r.accountHolderName != null)
            _DetailRow(
              icon: Icons.person_outline_rounded,
              label: 'Account name',
              value: r.accountHolderName!,
            ),
          if (reason != null || r.adminNote != null) ...[
            const SizedBox(height: AppSizes.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSizes.lg),
              decoration: BoxDecoration(
                color: reason != null
                    ? AppColors.danger.withValues(alpha: 0.08)
                    : AppColors.surfaceMuted,
                borderRadius: AppRadii.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reason != null
                        ? (r.status == 'rejected'
                              ? 'Rejection reason'
                              : 'Failure reason')
                        : 'Admin note',
                    style: AppText.bodyStrong.copyWith(
                      color: reason != null
                          ? AppColors.danger
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(reason ?? r.adminNote!, style: AppText.body),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSizes.lg),
          Text('Timeline', style: AppText.bodyStrong),
          const SizedBox(height: AppSizes.md),
          _Timeline(steps: _timelineFor(r)),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.caption),
                const SizedBox(height: 2),
                Text(value, style: AppText.bodyStrong),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.steps});
  final List<_TimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < steps.length; i++)
          _TimelineTile(step: steps[i], isLast: i == steps.length - 1),
      ],
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.step, required this.isLast});
  final _TimelineStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final reached = step.at != null;
    final dotColor = !reached
        ? AppColors.border
        : step.negative
        ? AppColors.danger
        : AppColors.success;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(
                  color: reached ? dotColor : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: dotColor, width: 2),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: reached ? dotColor : AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: AppText.bodyStrong.copyWith(
                      color: reached
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                    ),
                  ),
                  if (reached) ...[
                    const SizedBox(height: 2),
                    Text(_dateTimeLabel(step.at), style: AppText.caption),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
