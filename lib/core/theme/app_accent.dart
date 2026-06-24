import 'package:flutter/material.dart';
import 'app_colors.dart';

/// The single switchable accent palette for the app, delivered as a
/// [ThemeExtension] so it lives inside [ThemeData] and animates automatically
/// when the theme is swapped (via MaterialApp's built-in AnimatedTheme).
///
/// Neutrals (backgrounds, text, surfaces) stay as `const` [AppColors] — only
/// these accent roles change between the Mono and Lime themes, which keeps the
/// vast majority of the UI `const` (and fast).
@immutable
class AppAccent extends ThemeExtension<AppAccent> {
  const AppAccent({
    required this.isLime,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.onAccentSoft,
    required this.muted,
    required this.card,
    required this.highlight,
    required this.ring,
  });

  /// True when the Lime theme is active (lets a few widgets branch cleanly).
  final bool isLime;

  /// Strong accent fill (primary CTA background, active dots, badges).
  final Color accent;

  /// Foreground that sits on [accent].
  final Color onAccent;

  /// Soft tinted surface (icon tiles, chips).
  final Color accentSoft;

  /// Foreground that sits on [accentSoft].
  final Color onAccentSoft;

  /// Muted fill for soft buttons, unselected tabs, segmented tracks, banners —
  /// stays visible against the themed page background.
  final Color muted;

  /// Elevated content-card surface (transaction cards).
  final Color card;

  /// Accent text/colour used on DARK backgrounds (hero highlight word, the
  /// trust-score figure on the dark balance card).
  final Color highlight;

  /// Focus rings / active outlines.
  final Color ring;

  /// Black-and-white default theme.
  /// [_monoTile] — icon tiles & soft buttons (Enter Transaction Code, quick
  /// actions). [_monoContainer] — cards, tabs, segmented tracks.
  static const Color _monoTile = Color(0xFFE3E3E3);
  static const Color _monoContainer = Color(0xFFE9E9EC);
  static const AppAccent mono = AppAccent(
    isLime: false,
    accent: AppColors.ink,
    onAccent: AppColors.textOnDark,
    accentSoft: _monoTile,
    onAccentSoft: AppColors.textPrimary,
    muted: _monoContainer,
    card: _monoContainer,
    highlight: AppColors.textOnDark, // white on dark surfaces
    ring: AppColors.ink,
  );

  /// Lime theme.
  static const AppAccent lime = AppAccent(
    isLime: true,
    accent: AppColors.lime,
    onAccent: AppColors.ink,
    accentSoft: AppColors.limeSoft,
    onAccentSoft: AppColors.ink,
    muted: Color(0xFFE1E9C4), // muted lime — visible on the lime background
    card: Color(0xFFF7FAEC), // light lime-white card surface
    highlight: AppColors.lime,
    ring: AppColors.limeDeep,
  );

  static AppAccent of(BuildContext context) =>
      Theme.of(context).extension<AppAccent>() ?? mono;

  @override
  AppAccent copyWith({
    bool? isLime,
    Color? accent,
    Color? onAccent,
    Color? accentSoft,
    Color? onAccentSoft,
    Color? muted,
    Color? card,
    Color? highlight,
    Color? ring,
  }) {
    return AppAccent(
      isLime: isLime ?? this.isLime,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentSoft: accentSoft ?? this.accentSoft,
      onAccentSoft: onAccentSoft ?? this.onAccentSoft,
      muted: muted ?? this.muted,
      card: card ?? this.card,
      highlight: highlight ?? this.highlight,
      ring: ring ?? this.ring,
    );
  }

  @override
  AppAccent lerp(ThemeExtension<AppAccent>? other, double t) {
    if (other is! AppAccent) return this;
    return AppAccent(
      isLime: t < 0.5 ? isLime : other.isLime,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccentSoft: Color.lerp(onAccentSoft, other.onAccentSoft, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      card: Color.lerp(card, other.card, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      ring: Color.lerp(ring, other.ring, t)!,
    );
  }
}
