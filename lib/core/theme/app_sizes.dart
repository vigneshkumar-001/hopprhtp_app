import 'package:flutter/widgets.dart';

/// Common spacing, radius and duration tokens.
/// Keeps every screen visually consistent and easy to retune in one place.
class AppSizes {
  AppSizes._();

  // Spacing scale
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  // Horizontal screen padding used everywhere.
  static const double screenPad = 20;

  // Corner radii
  static const double rSm = 10;
  static const double rMd = 14;
  static const double rBtn = 16; // CTA buttons — rounded rectangle (not a pill)
  static const double rLg = 18;
  static const double rCard = 20; // elevated content cards
  static const double rXl = 24;
  static const double rPill = 100;

  // Common control heights
  static const double buttonHeight = 56;
  static const double fieldHeight = 56;
}

/// Animation/transition tokens — tuned for a snappy, smooth feel.
class AppDurations {
  AppDurations._();

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration page = Duration(milliseconds: 280);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuart;
}

/// Common rounded rect shapes derived from the radius tokens.
class AppRadii {
  AppRadii._();

  static final BorderRadius sm = BorderRadius.circular(AppSizes.rSm);
  static final BorderRadius md = BorderRadius.circular(AppSizes.rMd);
  static final BorderRadius lg = BorderRadius.circular(AppSizes.rLg);
  static final BorderRadius card = BorderRadius.circular(AppSizes.rCard);
  static final BorderRadius xl = BorderRadius.circular(AppSizes.rXl);
  static final BorderRadius btn = BorderRadius.circular(AppSizes.rBtn);
  static final BorderRadius pill = BorderRadius.circular(AppSizes.rPill);
}
