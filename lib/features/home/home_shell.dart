import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/notifications/notification_permission_prompt.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_logger.dart';
import '../../data/dto/transaction_dto.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/notification_permission_sheet.dart';
import '../auth/application/auth_controller.dart';
import '../profile/profile_screen.dart';
import '../transaction/create_transaction_screen.dart';
import 'home_screen.dart';
import 'spotlight_tour_overlay.dart';
import 'transactions_tab.dart';

/// How long a second back-press has to land in to actually exit.
const _exitPressWindow = Duration(seconds: 2);

/// TESTING ONLY. true = the onboarding tour shows on every app open,
/// regardless of the account's real `tutorialSeenAt` — set this while
/// you're actively testing the tour itself. false = the real behavior
/// (shows exactly once per account, per the backend's own record).
/// Guarded by `kDebugMode` below so this can NEVER show repeatedly for a
/// real user even if someone forgets to flip it back to false before a
/// release build — `flutter build` strips it to false automatically.
const bool kForceShowTourForTesting = false;

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

  /// A real, cancellable [Timer] rather than `Future.delayed` — a bare
  /// delayed Future has nothing to cancel, so a widget test that disposes
  /// this screen before the delay elapses trips flutter_test's "Timer still
  /// pending after dispose" assertion. Cancelling in [dispose] avoids that
  /// (and is simply correct: nothing should fire after this screen is gone).
  Timer? _notifPromptTimer;

  /// One real key per bottom-nav item, in the same order as [_BottomNav]'s
  /// own `_items` — the spotlight tour measures and highlights the ACTUAL
  /// rendered button through these, never a drawn stand-in for it.
  final _navItemKeys = List.generate(5, (_) => GlobalKey());

  /// Same idea, for the main buttons that live on the Home tab's content
  /// (not the always-visible bottom nav) — the tour spotlights these too,
  /// not just the nav bar.
  final _balanceCardKey = GlobalKey();
  final _activeStatKey = GlobalKey();
  final _coolingStatKey = GlobalKey();
  final _trustStatKey = GlobalKey();
  final _notificationBellKey = GlobalKey();
  final _createButtonKey = GlobalKey();
  final _enterCodeButtonKey = GlobalKey();

  bool _touring = false;

  @override
  void initState() {
    super.initState();
    // HomeShell is the permanent post-auth root (see AuthGate) — mounted
    // once per session, so this runs at most once per app open, never once
    // per tab switch. The delay lets the shell's own entrance settle first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifPromptTimer = Timer(
        const Duration(milliseconds: 1200),
        _runPostAuthChecks,
      );
    });
  }

  @override
  void dispose() {
    _notifPromptTimer?.cancel();
    super.dispose();
  }

  /// Runs, in order, the one-time-per-session prompts that shouldn't ever
  /// overlap: the onboarding tour (brand-new accounts only) first, then —
  /// only once that's dismissed — the notification re-ask. Sequential on
  /// purpose: stacking two full-screen/modal prompts on top of each other
  /// right after login would feel chaotic, not "world-class". The tour
  /// itself isn't awaited here (it's not a pushed route) — [_finishTour]
  /// picks up where this leaves off once the user actually dismisses it.
  Future<void> _runPostAuthChecks() async {
    if (!mounted) return;
    final user = ref.read(authControllerProvider).valueOrNull?.user;
    final forceForTesting = kDebugMode && kForceShowTourForTesting;
    if (user != null && (!user.hasSeenTutorial || forceForTesting)) {
      setState(() => _touring = true);
      return;
    }
    await _maybePromptNotifications();
  }

  /// Called once the tour finishes OR is skipped — both count as "seen".
  /// Marks it server-side, closes the overlay, then chains straight into
  /// the notification prompt so the two never race each other.
  Future<void> _finishTour() async {
    setState(() => _touring = false);
    try {
      await ref.read(authControllerProvider.notifier).markTutorialSeen();
    } catch (_) {
      // Best-effort — see the same reasoning on markTutorialSeen elsewhere;
      // never trap the user behind a failed network call here either.
    }
    await _maybePromptNotifications();
  }

  Future<void> _maybePromptNotifications() async {
    if (!mounted) return;
    if (!await NotificationPermissionPrompt.shouldShow()) return;
    if (!mounted) return;
    await showNotificationPermissionSheet(context);
  }

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
    final accent = AppAccent.of(context);
    final pages = [
      HomeScreen(
        onOpenProfile: () => setState(() => _index = 4),
        balanceCardKey: _balanceCardKey,
        activeStatKey: _activeStatKey,
        coolingStatKey: _coolingStatKey,
        trustStatKey: _trustStatKey,
        notificationBellKey: _notificationBellKey,
        createButtonKey: _createButtonKey,
        enterCodeButtonKey: _enterCodeButtonKey,
      ),
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
                child: _BottomNav(
                  index: _index,
                  onSelect: _select,
                  itemKeys: _navItemKeys,
                ),
              ),
            ),
            if (_touring)
              SpotlightTourOverlay(
                // Mixes the top balance summary, the main Home-screen action
                // buttons, and the always-visible bottom-nav essentials — not
                // bottom-nav-only. "Home" and "Send" are deliberately
                // skipped: Home is where the tour already is (spotlighting it
                // teaches nothing new), and Send opens the exact same screen
                // "Create Protected Transaction" below already covers, front
                // and center.
                steps: [
                  // The balance card's own numbers are explained one at a
                  // time (own step each) rather than all three crammed into
                  // one paragraph on the whole-card step below — easier to
                  // actually read while it's up for just a few seconds.
                  TourStep(
                    targetKey: _balanceCardKey,
                    title: 'Protected in Escrow',
                    description:
                        'This is your protected balance — money kept safe until each deal is complete.',
                    // Matches the card's own "escrow" highlight text.
                    ringColor: accent.highlight,
                  ),
                  TourStep(
                    targetKey: _activeStatKey,
                    title: 'Active',
                    description: 'Deals that are paid and on their way to delivery.',
                    // Matches this number's own white value colour on the card.
                    ringColor: AppColors.textOnDark,
                  ),
                  TourStep(
                    targetKey: _coolingStatKey,
                    title: 'Cooling',
                    description:
                        'Delivered, and waiting a short review period before the money is released.',
                    ringColor: AppColors.textOnDark,
                  ),
                  TourStep(
                    targetKey: _trustStatKey,
                    title: 'Trust Score',
                    description:
                        'Your rating from past deals — shown as a word like Fair or Good.',
                    // Matches this number's own highlight colour on the card.
                    ringColor: accent.highlight,
                  ),
                  TourStep(
                    targetKey: _notificationBellKey,
                    title: 'Notifications',
                    description:
                        'Stay updated — tap here anytime to see every alert on your deals.',
                    // Matches the bell glyph's own icon colour.
                    ringColor: accent.onAccentSoft,
                  ),
                  TourStep(
                    targetKey: _createButtonKey,
                    title: 'Create Protected Transaction',
                    description:
                        'Start a new escrow deal and send a payment link to your buyer.',
                    // Matches the button's own icon/label colour (white on
                    // its ink fill).
                    ringColor: AppColors.textOnDark,
                  ),
                  TourStep(
                    targetKey: _enterCodeButtonKey,
                    title: 'Enter Transaction Code',
                    description:
                        'Joining as a buyer? Enter the code your seller shared here.',
                    // Matches the button's own icon/label colour (dark on
                    // its soft fill).
                    ringColor: AppColors.textPrimary,
                  ),
                  TourStep(
                    targetKey: _navItemKeys[1],
                    title: 'Initiation',
                    description:
                        'Deals with payment and agreement still in progress live here.',
                    // Matches the nav item's own (unselected) icon colour.
                    ringColor: AppColors.textTertiary,
                  ),
                  TourStep(
                    targetKey: _navItemKeys[2],
                    title: 'Transit',
                    description:
                        'Track live deliveries and see what\'s in the cooling/review period.',
                    ringColor: AppColors.textTertiary,
                  ),
                  TourStep(
                    targetKey: _navItemKeys[4],
                    title: 'More',
                    description:
                        'Your profile, wallet, verification, and support — all in one place.',
                    ringColor: AppColors.textTertiary,
                  ),
                ],
                onFinish: _finishTour,
                onSkip: _finishTour,
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.index,
    required this.onSelect,
    required this.itemKeys,
  });
  final int index;
  final ValueChanged<int> onSelect;

  /// One [GlobalKey] per item, same order as [_items] — lets
  /// [SpotlightTourOverlay] measure and highlight the real rendered button.
  final List<GlobalKey> itemKeys;

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
                  key: itemKeys[i],
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
    super.key,
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
