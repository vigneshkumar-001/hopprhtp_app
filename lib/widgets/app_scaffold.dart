import 'package:flutter/material.dart';
import '../core/theme/app_accent.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_sizes.dart';
import '../core/theme/app_typography.dart';
import 'animations.dart';

/// Common screen shell used by every page so padding, app-bar style, the
/// back button and the optional pinned bottom action are identical everywhere.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.titleWidget,
    this.showBack = true,
    this.onBack,
    this.trailing,
    this.bottomAction,
    this.backgroundColor,
    this.scrollable = true,
    this.padding =
        const EdgeInsets.symmetric(horizontal: AppSizes.screenPad),
    this.stepTrailing,
    this.animate = true,
  });

  final Widget body;
  final String? title;
  final Widget? titleWidget;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;

  /// Pinned button(s) at the bottom (outside the scroll area).
  final Widget? bottomAction;
  /// When null, the themed scaffold background (Mono grey / Lime tint) is used.
  final Color? backgroundColor;
  final bool scrollable;
  final EdgeInsets padding;

  /// Small trailing label in the app bar (e.g. "1/4").
  final Widget? stepTrailing;

  /// Plays a subtle fade + slide-up entrance for the body on open.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final hasHeader =
        showBack || title != null || titleWidget != null || trailing != null;

    Widget content = padding == EdgeInsets.zero
        ? body
        : Padding(padding: padding, child: body);

    if (scrollable) {
      content = SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.only(bottom: AppSizes.xxl),
        child: content,
      );
    }

    if (animate) content = content.enter();

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (hasHeader) _Header(
              title: title,
              titleWidget: titleWidget,
              showBack: showBack,
              onBack: onBack,
              trailing: trailing ?? stepTrailing,
            ),
            Expanded(child: content),
            if (bottomAction != null)
              _BottomBar(child: bottomAction!),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    this.title,
    this.titleWidget,
    required this.showBack,
    this.onBack,
    this.trailing,
  });

  final String? title;
  final Widget? titleWidget;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.sm,
        AppSizes.md,
        AppSizes.sm,
      ),
      child: SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (titleWidget != null)
              titleWidget!
            else if (title != null)
              Text(title!, style: AppText.title),
            Align(
              alignment: Alignment.centerLeft,
              child: showBack
                  ? AppIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      // All back buttons use this fixed tint in the Lime theme;
                      // neutral accent tint in Mono.
                      background: AppAccent.of(context).isLime
                          ? const Color(0xFFE6E7DD)
                          : null,
                      onTap: onBack ?? () => Navigator.of(context).maybePop(),
                    )
                  : const SizedBox(width: 40),
            ),
            if (trailing != null)
              Align(alignment: Alignment.centerRight, child: trailing!),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Solid backdrop so the pinned action never shows scrolled content through
    // or around it, with a soft top shadow to lift it off the body.
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowSoft,
            blurRadius: 16,
            offset: Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        AppSizes.screenPad,
        AppSizes.md,
        AppSizes.screenPad,
        AppSizes.lg + MediaQuery.of(context).padding.bottom,
      ),
      child: child,
    );
  }
}

/// Common rounded-square icon button (back chevron, scan, swap, menu …).
/// Matches the squircle icon buttons used throughout the mockups.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.background,
    this.iconColor,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback? onTap;
  /// Null → themed accent tint (so the container stays visible & on-theme,
  /// e.g. lime in the Lime theme rather than grey that blends into the bg).
  final Color? background;
  final Color? iconColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    final bg = background ?? accent.accentSoft;
    final fg = iconColor ?? accent.onAccentSoft;
    final radius = BorderRadius.circular(size * 0.32);
    return Material(
      color: bg,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.46, color: fg),
        ),
      ),
    );
  }
}
