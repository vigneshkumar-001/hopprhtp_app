import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/dto/transaction_dto.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_loaders.dart';
import '../../widgets/feedback/state_views.dart';

class _Filter {
  const _Filter(this.label, {this.stage, this.status});
  final String label;
  final String? stage;
  final String? status;
}

/// Transaction history — backed by the paginated `/transactions` API with
/// infinite scroll: only ~15 rows are fetched at a time and the next page loads
/// as the user nears the bottom, keeping it fast even with many transactions.
class TransactionHistoryScreen extends ConsumerStatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  ConsumerState<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState
    extends ConsumerState<TransactionHistoryScreen> {
  static const _filters = [
    _Filter('All'),
    _Filter('Active', stage: 'active'),
    _Filter('Completed', stage: 'done'),
    _Filter('Disputed', status: 'disputed'),
  ];

  final _scroll = ScrollController();
  final List<ApiTransaction> _items = [];
  int _tab = 0;
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  bool _firstLoad = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 320) {
      _loadMore();
    }
  }

  Future<void> _loadFirst() async {
    setState(() {
      _items.clear();
      _page = 1;
      _hasMore = true;
      _firstLoad = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    final f = _filters[_tab];
    try {
      final page = await ref.read(transactionRepositoryProvider).listPage(
            page: _page,
            limit: 15,
            stage: f.stage,
            status: f.status,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasMore;
        _page += 1;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _firstLoad = false;
        });
      }
    }
  }

  void _selectTab(int i) {
    if (i == _tab) return;
    HapticFeedback.selectionClick();
    setState(() => _tab = i);
    _loadFirst();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Transaction History',
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.md),
          _tabs(),
          const SizedBox(height: AppSizes.lg),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _tabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (int i = 0; i < _filters.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: AppSizes.sm),
              child: GestureDetector(
                onTap: () => _selectTab(i),
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.md, vertical: AppSizes.sm),
                  decoration: BoxDecoration(
                    color: i == _tab ? AppColors.ink : AppColors.surfaceMuted,
                    borderRadius: AppRadii.pill,
                  ),
                  child: Text(
                    _filters[i].label,
                    style: AppText.label.copyWith(
                      color: i == _tab
                          ? AppColors.textOnDark
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _list() {
    if (_firstLoad && _loading) {
      return const Center(child: AppCircularLoader());
    }
    if (_error != null && _items.isEmpty) {
      return ErrorRetryView(message: friendlyError(_error!), onRetry: _loadFirst);
    }
    if (_items.isEmpty) {
      return const EmptyStateView(
        icon: Icons.receipt_long_rounded,
        title: 'No transactions yet',
        subtitle: 'Your protected deals will show up here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFirst,
      color: AppColors.ink,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSizes.xxl),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: AppSizes.md),
        itemBuilder: (context, i) =>
            i == _items.length ? _footer() : _HistoryCard(tx: _items[i]),
      ),
    );
  }

  Widget _footer() {
    if (_loading && _items.isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSizes.lg),
        child: Center(child: AppCircularLoader(size: 22, strokeWidth: 2.5)),
      );
    }
    if (_error != null && _items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.lg),
        child: Center(
          child: GestureDetector(
            onTap: _loadMore,
            child: Text('Tap to retry',
                style: AppText.caption
                    .copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
          ),
        ),
      );
    }
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.lg),
        child: Center(
          child: Text("That's everything",
              style:
                  AppText.caption.copyWith(color: AppColors.textTertiary)),
        ),
      );
    }
    return const SizedBox(height: AppSizes.lg);
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.tx});
  final ApiTransaction tx;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final (label, icon, fg, bg) = switch (tx.status) {
      ApiTxStatus.released ||
      ApiTxStatus.completed =>
        ('Released', Icons.check_rounded, AppColors.success, AppColors.successSoft),
      ApiTxStatus.disputed => (
          'Disputed',
          Icons.flag_outlined,
          AppColors.danger,
          AppColors.surfaceMuted
        ),
      ApiTxStatus.refunded => (
          'Refunded',
          Icons.undo_rounded,
          AppColors.textSecondary,
          AppColors.surfaceMuted
        ),
      ApiTxStatus.cancelled => (
          'Cancelled',
          Icons.close_rounded,
          AppColors.textSecondary,
          AppColors.surfaceMuted
        ),
      ApiTxStatus.cooling => (
          'Cooling',
          Icons.schedule_rounded,
          AppColors.textSecondary,
          AppColors.surfaceMuted
        ),
      _ => (
          tx.status.label,
          Icons.bolt_rounded,
          AppColors.textSecondary,
          AppColors.surfaceMuted
        ),
    };
    return AppCard(
      child: Row(
        children: [
          InitialsAvatar(initials: _initials(tx.merchantName), size: 42),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.merchantName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text('${tx.productName} · ${Dates.medium(tx.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Money.format(tx.grandTotalNaira), style: AppText.bodyStrong),
              const SizedBox(height: 4),
              StatusPill(
                  label: label,
                  icon: icon,
                  foreground: fg,
                  background: bg,
                  dense: true),
            ],
          ),
        ],
      ),
    );
  }
}
