import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// Shows a bottom sheet over a *blurred*, lightly-dimmed backdrop. The sheet
/// slides up while the blur fades in. Handles the drag handle, the bottom
/// safe-area (so content clears the system nav / home bar) and the keyboard
/// inset automatically.
///
/// [builder] receives the sheet's own context — use it to `Navigator.of(ctx).pop()`.
Future<T?> showBlurredSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false, // dismissal handled on the blur layer below
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (ctx, _, _) {
      final media = MediaQuery.of(ctx);
      return Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: AppColors.surface,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
            child: Padding(
              // Lift above the keyboard when a field is focused.
              padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
              child: SafeArea(
                top: false,
                // Bottom safe-area → content always clears the nav/home bar.
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(top: 12, bottom: 2),
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      builder(ctx),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return Stack(
        children: [
          // Blurred + faintly dimmed backdrop; tap anywhere here to dismiss.
          FadeTransition(
            opacity: anim,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(ctx).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: Container(color: Colors.black.withValues(alpha: 0.06)),
              ),
            ),
          ),
          SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        ],
      );
    },
  );
}
