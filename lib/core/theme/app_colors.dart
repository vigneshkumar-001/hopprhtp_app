import 'package:flutter/material.dart';

/// Central, single source of truth for every colour in the app.
/// Nothing in the UI should hard-code a [Color] — always reference [AppColors].
class AppColors {
  AppColors._();

  // ---- Brand / ink -------------------------------------------------------
  /// Near-black used for primary surfaces, buttons and the brand mark.
  static const Color ink = Color(0xFF0B0B0C);
  static const Color inkSoft = Color(0xFF16171A);

  // ---- Light surfaces ----------------------------------------------------
  /// App background on the light (post-auth / form) screens.
  static const Color background = Color(0xFFF1F1F2);
  /// Card / input background.
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEDEDEE);
  /// Soft tonal card (transaction cards) — a hair lighter than the page so it
  /// reads as a gentle floating container rather than a stark white block.
  static const Color cardSoft = Color(0xFFF6F6F8);

  // ---- Text --------------------------------------------------------------
  static const Color textPrimary = Color(0xFF0B0B0C);
  static const Color textSecondary = Color(0xFF6E6E73);
  static const Color textTertiary = Color(0xFF9A9AA0);
  static const Color textOnDark = Color(0xFFFFFFFF);
  static const Color textOnDarkMuted = Color(0xFFB7B7BC);

  // ---- Lines / borders ---------------------------------------------------
  static const Color border = Color(0xFFE4E4E6);
  static const Color borderStrong = Color(0xFF0B0B0C);
  static const Color divider = Color(0x14FFFFFF); // subtle on dark cards

  // ---- Lime accent (the "Lime" theme) ------------------------------------
  static const Color lime = Color(0xFFC5F03F);
  static const Color limeSoft = Color(0xFFEAF8C8);
  static const Color limeDeep = Color(0xFF7FB000);
  /// Soft lilac tile + its icon foreground, used for the profile menu-row icon
  /// boxes in the Lime theme (matches the reference design).
  static const Color lilacTile = Color(0xFFE6DEF6);
  static const Color onLilacTile = Color(0xFF6E55C8);
  /// Page background used across the app in the Lime theme.
  /// Kept a soft, low-intensity lime tint (close to white) so content stays
  /// legible and the theme feels light.
  static const Color limeBackground = Color(0xFFF8FAF1);

  // ---- Accents / status --------------------------------------------------
  static const Color success = Color(0xFF1FA463);
  static const Color successSoft = Color(0xFFE6F4EC);
  static const Color warning = Color(0xFFE08A1E);
  static const Color info = Color(0xFF2C6BE8);
  static const Color danger = Color(0xFFD64545);

  // ---- Misc --------------------------------------------------------------
  static const Color shadow = Color(0x14000000);
  static const Color shadowSoft = Color(0x0D000000); // gentle card elevation
  static const Color scrim = Color(0x66000000);
}
