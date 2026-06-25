import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'data/app_state.dart';
import 'features/auth/auth_gate.dart';
import 'widgets/theme_reveal.dart';

/// Root widget. Owns the single [AppState] and shares it through [AppScope].
class HopprApp extends StatefulWidget {
  const HopprApp({super.key, this.prefs});

  /// Persisted preferences (may be null in tests / if storage is unavailable).
  final SharedPreferences? prefs;

  @override
  State<HopprApp> createState() => _HopprAppState();
}

class _HopprAppState extends State<HopprApp> {
  late final AppState _state = AppState(prefs: widget.prefs);

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );
}
