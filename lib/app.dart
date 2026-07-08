import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/network/socket_service.dart';
import 'core/providers.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_logger.dart';
import 'data/app_state.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/auth_gate.dart';
import 'features/transaction/application/transactions_provider.dart';
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

  /// App-wide (not per-screen) — refreshes Home/History the moment ANY
  /// transaction event arrives for the signed-in user, whether or not they
  /// currently have that transaction's Details screen open. Per-transaction
  /// debouncing already happened inside [SocketService]; this only needs to
  /// invalidate the one shared list provider every screen reads from.
  StreamSubscription<TransactionSocketEvent>? _txEventsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(googleApiKeyProvider.future);
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _txEventsSub?.cancel();
    _state.dispose();
    super.dispose();
  }

  /// Self-heal on resume: a socket that silently died while backgrounded
  /// (dropped network, server restart, or a since-rotated access token — see
  /// [SocketService.ensureConnected]) gets a fresh reconnect attempt with the
  /// current token instead of staying dark until the user next logs out/in.
  /// A no-op while unauthenticated or already connected.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final authed =
        ref.read(authControllerProvider).valueOrNull?.isAuthenticated ?? false;
    if (authed) ref.read(socketServiceProvider).ensureConnected();
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
      } else if (!isNow && was) {
        ref.read(socketServiceProvider).disconnect();
      }
    });

    return AppScope(
      state: _state,
      child: ListenableBuilder(
        listenable: _state,
        builder: (context, _) => MaterialApp(
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
                child: ThemeReveal(child: child ?? const SizedBox.shrink()),
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
