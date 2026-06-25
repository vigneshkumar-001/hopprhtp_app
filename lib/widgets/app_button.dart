import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../core/theme/app_accent.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_sizes.dart';
import '../core/theme/app_typography.dart';
import 'feedback/app_loaders.dart';

enum AppButtonVariant { filled, outline, soft }

/// The single button used across the whole app.
/// Handles enabled/disabled/loading states and a subtle press scale so every
/// tap feels responsive and consistent.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.variant = AppButtonVariant.filled,
    this.enabled = true,
    this.loading = false,
    this.expand = true,
    this.haptic = true,
    this.accentInLime = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final AppButtonVariant variant;
  final bool enabled;
  final bool loading;
  final bool expand;

  /// When true, this CTA paints with the lime accent in the Lime theme while
  /// keeping its [variant] look in the Mono theme. Used for the "hero" CTA on
  /// each screen so the accent toggle reads clearly.
  final bool accentInLime;

  /// Fire a short vibration on tap. On by default so every primary action
  /// feels tactile; pass `false` for low-stakes buttons.
  final bool haptic;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _down = false;

  bool get _interactive =>
      widget.enabled && !widget.loading && widget.onPressed != null;

  void _handleTap() {
    if (widget.haptic) {
      // Stronger feedback for the primary (filled) action, lighter otherwise.
      if (widget.variant == AppButtonVariant.filled) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    }
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = !_interactive;
    final accent = AppAccent.of(context);
    final useAccent = accent.isLime && widget.accentInLime && !disabled;

    Color bg;
    Color fg;
    Border? border;
    switch (widget.variant) {
      case AppButtonVariant.filled:
        bg = disabled ? const Color(0xFFB9B9BC) : AppColors.ink;
        fg = AppColors.textOnDark;
        border = null;
      case AppButtonVariant.outline:
        bg = AppColors.surface;
        fg = AppColors.textPrimary;
        border = Border.all(color: AppColors.border, width: 1.4);
      case AppButtonVariant.soft:
        // Lime: a clearly-visible soft lime. Mono: the unified container grey
        // (matches the tiles / cards) with a hairline border for definition.
        bg = accent.isLime ? const Color(0xFFDDEEA0) : accent.accentSoft;
        fg = AppColors.textPrimary;
        border = accent.isLime
            ? null
            : Border.all(color: AppColors.border, width: 1.2);
    }

    if (useAccent) {
      bg = accent.accent;
      fg = accent.onAccent;
      border = null;
    }

    return Semantics(
      button: true,
      enabled: _interactive,
      label: widget.label,
      child: GestureDetector(
        onTapDown: _interactive ? (_) => setState(() => _down = true) : null,
        onTapUp: _interactive ? (_) => setState(() => _down = false) : null,
        onTapCancel:
            _interactive ? () => setState(() => _down = false) : null,
        onTap: _interactive ? _handleTap : null,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: AppDurations.fast,
          curve: AppDurations.easeOut,
          child: AnimatedContainer(
            duration: AppDurations.fast,
            height: AppSizes.buttonHeight,
            width: widget.expand ? double.infinity : null,
            padding: widget.expand
                ? null
                : const EdgeInsets.symmetric(horizontal: AppSizes.xl),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: AppRadii.btn,
              border: border,
            ),
            child: Center(
              child: widget.loading
                  ? AppButtonLoader(color: fg)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, size: 20, color: fg),
                          const SizedBox(width: AppSizes.sm),
                        ],
                        Text(widget.label,
                            style: AppText.button.copyWith(color: fg)),
                        if (widget.trailingIcon != null) ...[
                          const SizedBox(width: AppSizes.sm),
                          Icon(widget.trailingIcon, size: 20, color: fg),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
