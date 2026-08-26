import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/network/socket_service.dart';
import 'core/providers.dart';
import 'core/routing/app_transitions.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_logger.dart';
import 'data/app_state.dart';
import 'data/models/models.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/signin_screen.dart';
import 'features/update/update_gate.dart';
import 'features/profile/support_ticket_form_screen.dart';
import 'features/transaction/application/transactions_provider.dart';
import 'features/transaction/package_tracking_screen.dart';
import 'features/transaction/transaction_detail_screen.dart';
import 'features/wallet/withdrawal_history_screen.dart';
import 'widgets/feedback/connectivity_banner.dart';
import 'widgets/theme_reveal.dart';

/// Root widget. Owns the single [AppState] and shares it through [AppScope].
class HopprApp extends ConsumerStatefulWidget {
  const HopprApp({super.key, this.prefs});

  /// Persisted preferences (may be null in tests / if storage is unavailable).
  final SharedPreferences? prefs;

  @override
  ConsumerState<HopprApp> createState() => _HopprAppState();
}

class _HopprAppState extends ConsumerState<HopprApp>
    with WidgetsBindingObserver {
  late final AppState _state = AppState(prefs: widget.prefs);

  /// Lets push-notification taps navigate even when they arrive with no
  /// screen-owned [BuildContext] at hand (background/terminated launch).
  final _navigatorKey = GlobalKey<NavigatorState>();

  /// True from the moment the re-lock listener below pushes the overlay
  /// [SignInScreen], false from the moment it pops it — the source of truth
  /// for "do we currently own a pushed overlay that needs cleaning up",
  /// tracked directly rather than re-derived from AuthState transitions
  /// each time (see the listener's own comment for why that re-derivation
  /// doesn't work across `unlock()`'s loading hop).
  bool _lockScreenPushed = false;

  /// App-wide (not per-screen) — refreshes Home/History the moment ANY
  /// transaction event arrives for the signed-in user, whether or not they
  /// currently have that transaction's Details screen open. Per-transaction
  /// debouncing already happened inside [SocketService]; this only needs to
  /// invalidate the one shared list provider every screen reads from.
  StreamSubscription<TransactionSocketEvent>? _txEventsSub;

  /// A notification was tapped — see [PushNotificationService.transactionTaps].
  StreamSubscription<(String, String?)>? _pushTapSub;

  /// A withdrawal-lifecycle notification was tapped — see
  /// [PushNotificationService.withdrawalTaps].
  StreamSubscription<(String, String?)>? _pushWithdrawalTapSub;

  /// A support-ticket-replied notification was tapped — see
  /// [PushNotificationService.supportTicketTaps].
  StreamSubscription<(String, String?)>? _pushSupportTicketTapSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(googleApiKeyProvider.future);
      ref.read(feeSettingsProvider.future);
      final navigatorContext = _navigatorKey.currentContext;
      if (navigatorContext != null) {
        UpdateGate.check(navigatorContext, ref);
      }
    });
    _txEventsSub = ref.read(socketServiceProvider).events.listen((event) {
      AppLogger.debug(
        '[socket] provider invalidation triggered (global): '
        'transactionsProvider — tx=${event.transactionId}',
      );
      ref.invalidate(transactionsProvider);
      // Every lifecycle/dispute event that reaches this socket also created a
      // notification server-side — refresh the unread badge so the Home bell
      // updates in near-real-time instead of only on the next pull-to-refresh.
      ref.invalidate(unreadNotificationsProvider);
    });
    final push = ref.read(pushNotificationServiceProvider);
    push.init();
    _pushTapSub = push.transactionTaps.listen(_onPushTransactionTap);
    _pushWithdrawalTapSub = push.withdrawalTaps.listen(_onPushWithdrawalTap);
    _pushSupportTicketTapSub = push.supportTicketTaps.listen(
      _onPushSupportTicketTap,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _txEventsSub?.cancel();
    _pushTapSub?.cancel();
    _pushWithdrawalTapSub?.cancel();
    _pushSupportTicketTapSub?.cancel();
    _state.dispose();
    super.dispose();
  }

  /// Opens the real transaction a notification pointed at — always re-fetched
  /// from the backend first (source of truth), the tapped payload only ever
  /// supplies the id (+ a `screen` routing hint), never the data shown on
  /// screen. `screen == 'track_package'` (from `dispatcher_nearby`) opens
  /// Track Package only when it's actually meaningful for the transaction's
  /// current status (same gate the screen's own button uses) — otherwise it
  /// falls back to Transaction Details, same as every other event.
  Future<void> _onPushTransactionTap((String, String?) tap) async {
    final (transactionId, screen) = tap;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    try {
      final tx = await ref
          .read(transactionRepositoryProvider)
          .getById(transactionId);
      final escrowTx = EscrowTransaction.fromApi(tx);
      final openTrackPackage =
          screen == 'track_package' &&
          isTrackableTransactionStatus(escrowTx.apiStatus);
      navigator.push(
        AppNav.route(
          openTrackPackage
              ? PackageTrackingScreen(tx: escrowTx)
              : TransactionDetailScreen(tx: escrowTx),
        ),
      );
    } catch (e) {
      AppLogger.debug('[push] could not open transaction $transactionId: $e');
    }
  }

  /// Opens Withdrawal History for a tapped withdrawal-lifecycle notification
  /// (under review/approved/paid/rejected/failed). The payload's
  /// withdrawalId is never trusted as data — it's only used so
  /// [WithdrawalHistoryScreen] can auto-open that specific request's detail
  /// sheet once it has fetched the real, current list from the backend.
  void _onPushWithdrawalTap((String, String?) tap) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    final (withdrawalId, _) = tap;
    navigator.push(
      AppNav.route(
        WithdrawalHistoryScreen(
          openWithdrawalId: withdrawalId.isEmpty ? null : withdrawalId,
        ),
      ),
    );
  }

  /// Opens the support form/tracking screen for a tapped "support replied"
  /// notification — no per-ticket detail screen exists yet, and "My support
  /// requests" there already shows real, freshly-fetched status for every
  /// ticket (including the admin's reply).
  void _onPushSupportTicketTap((String, String?) tap) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(AppNav.route(const SupportTicketFormScreen()));
  }

  /// Two independent lifecycle reactions:
  ///  - On `paused` (app backgrounded): re-lock a biometric-protected session
  ///    immediately, so by the time the user switches back — or glances at
  ///    the OS app-switcher preview — the dashboard is already hidden behind
  ///    a fresh biometric/PIN check instead of resuming straight to it. A
  ///    no-op when biometric unlock is off (session just resumes normally,
  ///    unchanged default behaviour) — see [AuthController.relockIfBiometricEnabled].
  ///  - On `resumed`: self-heal a socket that silently died while
  ///    backgrounded (dropped network, server restart, or a since-rotated
  ///    access token — see [SocketService.ensureConnected]) instead of
  ///    staying dark until the user next logs out/in. A no-op while
  ///    unauthenticated or already connected.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      ref.read(authControllerProvider.notifier).relockIfBiometricEnabled();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final authed =
        ref.read(authControllerProvider).valueOrNull?.isAuthenticated ?? false;
    if (authed) ref.read(socketServiceProvider).ensureConnected();
    // Also re-check the update gate on every foreground, not just cold
    // start — an admin can flip Force Update while the app is already
    // running in someone's pocket, and the sheet should catch them the next
    // time they switch back to it, not only on their next full app launch.
    ref.invalidate(appUpdateInfoProvider);
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext != null) {
      UpdateGate.check(navigatorContext, ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Realtime connection follows the session, not any one screen: connect
    // the moment the user is authenticated (cold-start session restore,
    // login, register, biometric unlock — every path resolves through
    // authControllerProvider), disconnect the moment they aren't (logout,
    // forced logout on refresh-token expiry). No socket calls needed inside
    // AuthController itself — this single listener covers every transition.
    ref.listen<AsyncValue<AuthState>>(authControllerProvider, (previous, next) {
      final was = previous?.valueOrNull?.isAuthenticated ?? false;
      final isNow = next.valueOrNull?.isAuthenticated ?? false;
      if (isNow && !was) {
        ref.read(socketServiceProvider).connect();
        ref.read(pushNotificationServiceProvider).registerToken();
      } else if (!isNow && was) {
        ref.read(socketServiceProvider).disconnect();
      }

      // Warm re-lock (app was already open, mid-navigation, then backgrounded
      // — see AuthController.relockIfBiometricEnabled): push SignInScreen
      // (in overlay mode — see its own doc comment) ON TOP of wherever the
      // user currently is, instead of letting AuthGate's own root-content
      // swap handle it (that would only be reachable by popping back to the
      // root, which used to also destroy whatever screen the user was on —
      // real apps return you to the exact same screen after unlocking, not
      // to Home). Cold-start-locked (no prior screen to preserve) still goes
      // through AuthGate's own SignInScreen branch (isOverlay: false there),
      // not this push. The same SignInScreen widget either way — one bare
      // "Locked" placeholder screen (the old dedicated LockScreen) was
      // exactly the extra, less-polished UI this unification removes.
      //
      // Whether that pushed overlay should come back down is deliberately
      // NOT decided by diffing `previous`/`next` here: unlock() always goes
      // locked -> AsyncLoading() -> resolved, and a bare AsyncLoading carries
      // no value, so `next.valueOrNull?.isLocked` reads false the instant
      // the loading tick fires — well before the actual outcome (unlocked,
      // still dead, or rejected) is known. Comparing adjacent pairs across
      // that hop used to either act on "still waiting on the network" as if
      // it were a decided outcome, or (once `previous` was itself the
      // loading tick) never fire at all. `_lockScreenPushed` sidesteps the
      // whole problem — it just tracks whether *we* currently own a pushed
      // overlay, independent of how many loading ticks land in between.
      final isNowLocked = next.valueOrNull?.isLocked ?? false;
      final navigator = _navigatorKey.currentState;
      if (was && !_lockScreenPushed && isNowLocked && navigator != null) {
        _lockScreenPushed = true;
        navigator.push(AppNav.route<void>(const SignInScreen(isOverlay: true)));
      } else if (_lockScreenPushed && !next.isLoading) {
        // The pending unlock attempt has settled — pop the overlay exactly
        // once, now that the actual outcome is known. A manual PIN sign-in
        // typed directly into the overlay lands here too (see
        // SignInScreen.isOverlay's doc comment for why it doesn't also try
        // to pop itself).
        _lockScreenPushed = false;
        if (isNow) {
          // Unlocked — reveal the exact screen that was underneath, untouched.
          if (navigator != null && navigator.canPop()) navigator.pop();
        } else {
          // The locked session turned out to be dead — biometrics succeeded
          // locally but the stored token was rejected server-side (session
          // expired / revoked), or the account was found frozen/deleted
          // while restoring it. AuthGate's own listener deliberately skips
          // its session-ended cleanup for any transition through `locked`
          // (see its comment) and leaves this to us — so do that cleanup
          // here: clear the whole stack, not just pop the overlay, so the
          // person lands on sign-in fresh instead of the stale authenticated
          // screen that was underneath it.
          navigator?.popUntil((r) => r.isFirst);
          final navigatorContext = _navigatorKey.currentContext;
          if (navigatorContext != null) {
            AppScope.read(navigatorContext).signOut();
          }
        }
      }
    });

    return AppScope(
      state: _state,
      child: ListenableBuilder(
        listenable: _state,
        builder: (context, _) => MaterialApp(
          navigatorKey: _navigatorKey,
          navigatorObservers: [ClearSnackBarsOnNavigate()],
          title: 'Hoppr',
          debugShowCheckedModeBanner: false,
          // Kept short: the circular ThemeReveal (below) is the headline
          // animation; this is just the crisp settle / fallback under it.
          themeAnimationDuration: const Duration(milliseconds: 200),
          themeAnimationCurve: Curves.easeInOutCubic,
          theme: _state.limeTheme ? AppTheme.lime : AppTheme.mono,
          // Cap text scaling so the dense UI never breaks on large-font devices.
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final bg = Theme.of(context).scaffoldBackgroundColor;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              // System status/navigation bars follow the themed background, so
              // the app is themed edge-to-edge. Screens with a dark backdrop
              // (onboarding) override this with their own lighter icons.
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
                systemNavigationBarColor: bg,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
              child: MediaQuery(
                data: media.copyWith(
                  textScaler: media.textScaler.clamp(
                    minScaleFactor: 0.9,
                    maxScaleFactor: 1.15,
                  ),
                ),
                // Stacked once, above whatever screen is showing, so the
                // offline banner appears/disappears app-wide with no
                // per-screen wiring — see ConnectivityBanner's own doc.
                child: Stack(
                  children: [
                    ThemeReveal(child: child ?? const SizedBox.shrink()),
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: ConnectivityBanner(),
                    ),
                  ],
                ),
              ),
            );
          },
          home: const AuthGate(),
        ),
      ),
    );
  }
}

/// Sets up edge-to-edge system UI before the app starts.
void configureSystemUi() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}
