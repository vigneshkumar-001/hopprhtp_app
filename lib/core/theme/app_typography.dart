import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Common text styles. Uses the platform default family (no network fonts)
/// but tuned weights / spacing to match the bold, tight-leading mockups.
class AppText {
  AppText._();

  /// The single app-wide font family (open-source twin of iOS' SF Pro).
  static const String fontFamily = 'Inter';
  static const String _family = fontFamily;

  static const TextStyle display = TextStyle(
    fontFamily: _family,
    fontSize: 40,
    height: 1.02,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.2,
    color: AppColors.textPrimary,
  );

  static const TextStyle h1 = TextStyle(
    fontFamily: _family,
    fontSize: 25,
    height: 1.12,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    color: AppColors.textPrimary,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: _family,
    fontSize: 20,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: _family,
    fontSize: 16.5,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  static const TextStyle title = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _family,
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontFamily: _family,
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle label = TextStyle(
    fontFamily: _family,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    color: AppColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _family,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    color: AppColors.textTertiary,
  );

  static const TextStyle button = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
    color: AppColors.textOnDark,
  );

  /// Big numeric/balance style used on dark cards.
  static const TextStyle numeral = TextStyle(
    fontFamily: _family,
    fontSize: 31,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    color: AppColors.textOnDark,
  );
}
