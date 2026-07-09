import 'package:flutter/material.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/dto/notification_dto.dart';
import '../../data/models/models.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/feedback/app_loaders.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/state_views.dart';
import '../transaction/transaction_detail_screen.dart';

IconData _iconFor(String type) => switch (type) {
  'payment' => Icons.account_balance_wallet_outlined,
  'payout' => Icons.account_balance_outlined,
  'delivery' => Icons.local_shipping_outlined,
  'dispute' => Icons.flag_outlined,
  'transaction' => Icons.receipt_long_outlined,
  _ => Icons.notifications_none_rounded,
};

/// The home app-bar bell with a live unread badge.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref
        .watch(unreadNotificationsProvider)
        .maybeWhen(data: (n) => n, orElse: () => 0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppIconButton(icon: FeatherIcons.bell, onTap: onTap),
        if (unread > 0)
          Positioned(
            right: -3,
            top: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.surface, width: 1.5),
              ),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final _scroll = ScrollController();
  final List<AppNotification> _items = [];
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
    try {
      final page = await ref
          .read(notificationRepositoryProvider)
          .listPage(page: _page, limit: 20);
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
        AppSnackbar.error(context, friendlyError(e), onRetry: _loadFirst);
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

  Future<void> _open(AppNotification n) async {
    // Optimistically mark read (only if it was unread), then open the related
    // transaction so a tapped notification lands somewhere useful.
    if (!n.read) {
      setState(() {
        final i = _items.indexWhere((x) => x.id == n.id);
        if (i != -1) _items[i] = _readCopy(n);
      });
      try {
        await ref.read(notificationRepositoryProvider).markRead(n.id);
        ref.invalidate(unreadNotificationsProvider);
      } catch (_) {
        /* optimistic — stays read locally */
      }
    }
    await _openTarget(n);
  }

  /// Best-effort deep link: a notification carries the transaction's public
  /// code, so fetch that transaction and open its detail (which surfaces the
  /// dispute card for dispute notifications). A missing/inaccessible code just
  /// doesn't navigate — never an error to the user.
  Future<void> _openTarget(AppNotification n) async {
    final code = (n.code ?? '').trim();
    if (code.isEmpty) return;
    try {
      final tx = await ref.read(transactionRepositoryProvider).getByCode(code);
      if (!mounted) return;
      AppNav.push(
        context,
        TransactionDetailScreen(tx: EscrowTransaction.fromApi(tx)),
      );
    } catch (_) {
      // Best-effort — no navigation if the transaction can't be loaded.
    }
  }

  Future<void> _markAllRead() async {
    setState(() {
      for (var i = 0; i < _items.length; i++) {
        if (!_items[i].read) _items[i] = _readCopy(_items[i]);
      }
    });
    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
      ref.invalidate(unreadNotificationsProvider);
      if (mounted) AppSnackbar.success(context, 'All caught up');
    } catch (_) {
      if (mounted) AppSnackbar.error(context, "Couldn't mark all as read.");
    }
  }

  AppNotification _readCopy(AppNotification n) => AppNotification(
    id: n.id,
    type: n.type,
    title: n.title,
    body: n.body,
    code: n.code,
    read: true,
    createdAt: n.createdAt,
  );

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((n) => !n.read);
    return AppScaffold(
      title: 'Notifications',
      scrollable: false,
      trailing: hasUnread
          ? GestureDetector(
              onTap: _markAllRead,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.md,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: AppRadii.pill,
                ),
                child: Text(
                  'Mark read',
                  style: AppText.caption.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.only(top: AppSizes.sm),
        child: _list(),
      ),
    );
  }

  Widget _list() {
    if (_firstLoad && _loading) {
      return const Center(child: AppCircularLoader());
    }
    if (_items.isEmpty) {
      return const EmptyStateView(
        icon: Icons.notifications_none_rounded,
        title: 'No notifications yet',
        subtitle: 'Updates about your transactions will appear here.',
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
        separatorBuilder: (_, _) => const SizedBox(height: AppSizes.sm),
        itemBuilder: (context, i) => i == _items.length
            ? _footer()
            : _NotificationCard(
                notice: _items[i],
                onTap: () => _open(_items[i]),
              ),
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
    if (!_hasMore) return const SizedBox(height: AppSizes.lg);
    return const SizedBox(height: AppSizes.lg);
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notice, required this.onTap});
  final AppNotification notice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    final unread = !notice.read;
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: unread ? accent.accentSoft : AppColors.surfaceMuted,
              borderRadius: AppRadii.sm,
            ),
            child: Icon(
              _iconFor(notice.type),
              size: 19,
              color: unread ? accent.onAccentSoft : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notice.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyStrong,
                      ),
                    ),
                    if (unread) ...[
                      const SizedBox(width: AppSizes.sm),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.ink,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(notice.body, style: AppText.caption),
                if (notice.createdAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    Dates.relative(notice.createdAt!),
                    style: AppText.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
