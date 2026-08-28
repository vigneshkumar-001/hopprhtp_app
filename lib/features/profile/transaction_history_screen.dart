import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/network/socket_service.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_logger.dart';
import '../../data/dto/transaction_dto.dart';
import '../../data/models/models.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/feedback/app_loaders.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/state_views.dart';
import '../../widgets/transaction_card.dart';
import '../transaction/transaction_detail_screen.dart';

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
  const TransactionHistoryScreen({super.key, this.initialStage});

  /// Pre-selects the matching tab (e.g. from Home's "View All") — null opens
  /// on the unfiltered "All" tab.
  final ApiTxStage? initialStage;

  @override
  ConsumerState<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState
    extends ConsumerState<TransactionHistoryScreen>
    with WidgetsBindingObserver {
  static const _filters = [
    _Filter('All'),
    _Filter('Active', stage: 'active'),
    _Filter('Cooling', stage: 'cooling'),
    _Filter('Completed', stage: 'done'),
    _Filter('Disputed', status: 'disputed'),
  ];

  final _scroll = ScrollController();
  final _searchController = TextEditingController();
  final List<ApiTransaction> _items = [];
  int _tab = 0;
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  bool _firstLoad = true;
  Object? _error;
  String _search = '';
  Timer? _searchDebounce;

  // This screen keeps its own paginated `_items` list rather than watching
  // `transactionsProvider` (infinite-scroll pagination doesn't map cleanly
  // onto a single cached list) — which means app.dart's global socket
  // listener invalidating that provider has no effect here. This subscription
  // is what actually keeps History live: any transaction event for this user
  // (payment, delivery, dispute...) reloads page 1, same as pull-to-refresh.
  StreamSubscription<TransactionSocketEvent>? _socketSub;
  Timer? _reloadDebounce;
  late final SocketService _socket;

  @override
  void initState() {
    super.initState();
    _tab = _tabIndexFor(widget.initialStage);
    _scroll.addListener(_onScroll);
    _loadFirst();

    WidgetsBinding.instance.addObserver(this);
    _socket = ref.read(socketServiceProvider);
    _socketSub = _socket.events.listen((event) {
      AppLogger.debug(
        '[socket] history reload scheduled: tx=${event.transactionId} '
        'type=${event.type}',
      );
      _scheduleReload();
    });
  }

  static int _tabIndexFor(ApiTxStage? stage) {
    if (stage == null) return 0; // "All"
    final i = _filters.indexWhere((f) => f.stage == stage.name);
    return i == -1 ? 0 : i;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _socketSub?.cancel();
    _reloadDebounce?.cancel();
    _searchDebounce?.cancel();
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Fallback for when the socket never connects or is mid-reconnect: coming
  /// back to the foreground re-syncs History the same way
  /// TransactionDetailScreen re-syncs on resume.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadFirst();
  }

  /// Coalesces a burst of socket events (e.g. payment + escrow-funded firing
  /// close together) into a single page-1 reload instead of reloading once
  /// per event.
  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _loadFirst();
    });
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
      final page = await ref
          .read(transactionRepositoryProvider)
          .listPage(
            page: _page,
            limit: 15,
            stage: f.stage,
            status: f.status,
            search: _search.isEmpty ? null : _search,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasMore;
        _page += 1;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e);
        AppSnackbar.error(
          context,
          friendlyError(e),
          onRetry: _loadFirst,
          autoRetryOnReconnect: e is ApiException && e.isConnectionIssue,
        );
      }
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

  /// Rebuilds immediately (so the clear button appears/disappears without
  /// lag) but only actually re-queries the server 400ms after typing stops —
  /// searching on every keystroke would fire a request per letter.
  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      final next = value.trim();
      if (next == _search) return;
      setState(() => _search = next);
      _loadFirst();
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _search = '');
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
          _searchField(),
          const SizedBox(height: AppSizes.md),
          _tabs(),
          const SizedBox(height: AppSizes.lg),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _searchField() {
    return AppTextField(
      controller: _searchController,
      icon: Icons.search_rounded,
      hint: 'Search by code, item, or amount',
      textInputAction: TextInputAction.search,
      onChanged: _onSearchChanged,
      onSubmitted: _onSearchChanged,
      trailing: _searchController.text.isEmpty
          ? null
          : GestureDetector(
              onTap: _clearSearch,
              child: const Icon(
                Icons.close_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
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
                    horizontal: AppSizes.md,
                    vertical: AppSizes.sm,
                  ),
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
    if (_items.isEmpty) {
      return _search.isEmpty
          ? const EmptyStateView(
              icon: Icons.receipt_long_rounded,
              title: 'No transactions yet',
              subtitle: 'Your protected deals will show up here.',
            )
          : EmptyStateView(
              icon: Icons.search_off_rounded,
              title: 'No matches for "$_search"',
              subtitle: 'Try a different code, item name, or amount.',
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
        itemBuilder: (context, i) {
          if (i == _items.length) return _footer();
          // Same premium card used on Home, so history reads as one
          // consistent design instead of a plain, separate row style.
          final tx = EscrowTransaction.fromApi(_items[i]);
          return TransactionCard(
            tx: tx,
            colorIndex: i,
            productFirstLayout: true,
            onTap: () => AppNav.push(context, TransactionDetailScreen(tx: tx)),
          );
        },
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
            child: Text(
              'Tap to retry',
              style: AppText.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
      );
    }
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.lg),
        child: Center(
          child: Text(
            'No more transactions',
            style: AppText.caption.copyWith(color: AppColors.textTertiary),
          ),
        ),
      );
    }
    return const SizedBox(height: AppSizes.lg);
  }
}
