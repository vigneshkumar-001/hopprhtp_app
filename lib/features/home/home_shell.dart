import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_logger.dart';
import '../../data/dto/transaction_dto.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../profile/profile_screen.dart';
import '../transaction/create_transaction_screen.dart';
import 'home_screen.dart';
import 'transactions_tab.dart';

/// How long a second back-press has to land in to actually exit.
const _exitPressWindow = Duration(seconds: 2);

/// The post-auth container with the bottom navigation bar (mockup 5).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  bool _navVisible = true;

  /// Set on the first back-press while already on Home — a second press
  /// landing within [_exitPressWindow] exits the app instead of showing the
  /// warning again.
  DateTime? _lastBackPressAt;

  /// This screen is the app's permanent root route (see `AuthGate`) — Android
  /// back here would otherwise close the app immediately. Deeper screens are
  /// pushed as their own routes on top of this one, so their own back
  /// gesture pops them normally and never reaches this handler at all.
  void _handleBackInvoked(bool didPop, Object? result) {
    if (didPop) return;
    if (_index != 0) {
      // Not on Home — first back returns to Home instead of exiting.
      setState(() => _index = 0);
      return;
    }
    final now = DateTime.now();
    final last = _lastBackPressAt;
    if (last != null && now.difference(last) < _exitPressWindow) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPressAt = now;
    AppSnackbar.info(context, 'Press back again to exit Hoppr');
  }

  void _select(int i) {
    // "Send" (3) opens Create Transaction (seller creates + sends the
    // payment link) — an action, never a tab. The identity-verification
    // gate runs INSIDE CreateTransactionScreen itself once it's on screen,
    // so an unverified seller still sees the real screen first, blurred
    // behind the gate sheet, rather than being blocked before it opens.
    // Every other index (Home, Initiation, Transit, More) switches the
    // visible tab. Joining a transaction by code moved to the Initiation
    // tab's top action — Send is seller-only now.
    if (i == 3) {
      AppLogger.debug('Send tab opened Create Transaction');
      AppNav.push(context, const CreateTransactionScreen());
      return;
    }
    setState(() {
      _index = i;
      _navVisible = true; // always reveal the bar when switching tabs
    });
  }

  /// Hide the floating bar while scrolling down, reveal it when scrolling up.
  bool _onScroll(UserScrollNotification n) {
    final dir = n.direction;
    if (dir == ScrollDirection.reverse && _navVisible) {
      setState(() => _navVisible = false);
    } else if (dir == ScrollDirection.forward && !_navVisible) {
      setState(() => _navVisible = true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onOpenProfile: () => setState(() => _index = 4)),
      // Created/payment stage, delivery not started yet.
      const TransactionsTab(
        title: 'Initiation',
        subtitle: 'Payment & agreement in progress',
        statuses: {
          ApiTxStatus.draft,
          ApiTxStatus.awaitingAgreement,
          ApiTxStatus.awaitingPayment,
          ApiTxStatus.paymentReceived,
          ApiTxStatus.awaitingDispatch,
        },
        emptyTitle: 'No transactions in progress',
        emptySubtitle: 'New payment-stage deals will appear here.',
        // Buyer-side "join by code" entry now lives here — Send is seller-only.
        showJoinAction: true,
      ),
      // Delivery in progress through cooling (and disputes raised during it).
      const TransactionsTab(
        title: 'Transit',
        subtitle: 'Delivery & cooling period',
        statuses: {
          ApiTxStatus.inTransit,
          ApiTxStatus.outForDelivery,
          ApiTxStatus.delivered,
          ApiTxStatus.cooling,
          ApiTxStatus.disputed,
        },
        emptyTitle: 'Nothing in transit',
        emptySubtitle: 'Deliveries and cooling-period deals will appear here.',
      ),
      const SizedBox.shrink(), // placeholder for the Send action slot
      const ProfileScreen(embedded: true),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleBackInvoked,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        // Floating bar overlays the content so it can slide away on scroll.
        body: Stack(
          children: [
            NotificationListener<UserScrollNotification>(
              onNotification: _onScroll,
              // Only the visible tab takes part in Hero animations — otherwise the
              // offstage tabs would duplicate hero tags (IndexedStack keeps all
              // children mounted).
              child: IndexedStack(
                index: _index,
                children: [
                  for (int i = 0; i < pages.length; i++)
                    HeroMode(enabled: _index == i, child: pages[i]),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSlide(
                offset: _navVisible ? Offset.zero : const Offset(0, 1.6),
                duration: AppDurations.normal,
                curve: AppDurations.easeOut,
                child: _BottomNav(index: _index, onSelect: _select),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  // Order & icons mirror the mockup exactly. Thin Feather line icons; the
  // active item is distinguished by colour + label weight (not a filled icon).
  // Home · Initiation(⚡) · Transit(🚚) · Send(→) · More
  static const _items = [
    (FeatherIcons.home, 'Home'),
    (FeatherIcons.zap, 'Initiation'),
    (FeatherIcons.truck, 'Transit'),
    (FeatherIcons.arrowRight, 'Send'),
    (FeatherIcons.user, 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    // Floating, centered pill — inset from the edges, rounded on all sides,
    // with a soft drop shadow. It slides off-screen on scroll (see HomeShell).
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSizes.lg,
        AppSizes.sm,
        AppSizes.lg,
        AppSizes.md + MediaQuery.of(context).padding.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(
          vertical: AppSizes.xs,
          horizontal: AppSizes.sm,
        ),
        child: Row(
          children: [
            for (int i = 0; i < _items.length; i++)
              Expanded(
                child: _NavItem(
                  icon: _items[i].$1,
                  label: _items[i].$2,
                  selected:
                      index == i, // Send (i==3) is an action, never selected
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
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
    final color = selected ? AppColors.textPrimary : AppColors.textTertiary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppText.caption.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
