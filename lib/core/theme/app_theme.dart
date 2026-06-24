import 'package:flutter/material.dart';
import 'app_accent.dart';
import 'app_colors.dart';
import 'app_sizes.dart';
import 'app_typography.dart';
import '../routing/app_transitions.dart';

/// The two switchable [ThemeData]s for the whole app.
/// Both share identical neutrals; they differ only in the [AppAccent]
/// extension (and the colour-scheme accent roles).
class AppTheme {
  AppTheme._();

  /// Black-and-white default theme.
  static ThemeData get mono => _build(AppAccent.mono);

  /// Lime accent theme.
  static ThemeData get lime => _build(AppAccent.lime);

  /// Backwards-compatible alias.
  static ThemeData get light => mono;

  static ThemeData _build(AppAccent accent) {
    // The Lime theme tints the whole page background; Mono stays neutral.
    final bg =
        accent.isLime ? AppColors.limeBackground : AppColors.background;
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: AppText.fontFamily,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[accent],
      colorScheme: ColorScheme.light(
        primary: AppColors.ink,
        onPrimary: AppColors.textOnDark,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        secondary: accent.accent,
        onSecondary: accent.onAccent,
        error: AppColors.danger,
      ),
    );

    return base.copyWith(
      // Smooth, common transition for every MaterialPageRoute on every platform.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SharedAxisPageTransitionsBuilder(),
          TargetPlatform.iOS: SharedAxisPageTransitionsBuilder(),
          TargetPlatform.macOS: SharedAxisPageTransitionsBuilder(),
          TargetPlatform.windows: SharedAxisPageTransitionsBuilder(),
          TargetPlatform.linux: SharedAxisPageTransitionsBuilder(),
          TargetPlatform.fuchsia: SharedAxisPageTransitionsBuilder(),
        },
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: AppText.title,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: AppText.bodyStrong.copyWith(color: AppColors.textOnDark),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.md),
      ),
    );
  }
}
