import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/models.dart';
import '../profile/profile_screen.dart';
import '../transaction/create_transaction_screen.dart';
import '../transaction/enter_transaction_code_screen.dart';
import '../transaction/package_tracking_screen.dart';
import 'home_screen.dart';
import 'transactions_tab.dart';

/// The post-auth container with the bottom navigation bar (mockup 5).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _navVisible = true;

  void _select(int i) {
    // "Initiation" (1) opens the Create Transaction flow; "Send" (3) opens the
    // Enter Transaction Code screen. Neither switches to a tab.
    if (i == 1) {
      AppNav.push(context, const CreateTransactionScreen());
      return;
    }
    if (i == 3) {
      AppNav.push(context, const EnterTransactionCodeScreen());
      return;
    }
    // "Transit" (2) opens the Package on the way tracking screen.
    if (i == 2) {
      AppNav.push(
        context,
        PackageTrackingScreen(
          draft: PaymentDraft(
            productName: 'MacBook Pro M2',
            sellerName: 'Yemi Stores',
            sellerCode: 'HTP-LGS-8881',
            itemSubtotal: 1230087,
          ),
        ),
      );
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
      const SizedBox.shrink(), // Initiation → opens Create Transaction (action)
      const TransactionsTab(
        title: 'In transit',
        subtitle: 'On the move to your buyers',
        stage: TxStage.active,
        statusFilter: TxStatus.inTransit,
      ),
      const SizedBox.shrink(), // placeholder for the Send action slot
      const ProfileScreen(embedded: true),
    ];

    return Scaffold(
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
            vertical: AppSizes.xs, horizontal: AppSizes.sm),
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
