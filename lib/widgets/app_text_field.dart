import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_sizes.dart';
import '../core/theme/app_typography.dart';

/// The common labelled input used on every form.
/// White rounded field with a leading icon; border goes black on focus to
/// match the mockups. Optional trailing action (e.g. "Show").
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.icon,
    this.keyboardType,
    this.obscure = false,
    this.trailing,
    this.inputFormatters,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.prefixText,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final IconData? icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? trailing;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final String? prefixText;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final FocusNode _focus = FocusNode()..addListener(_onFocus);
  bool _focused = false;

  void _onFocus() => setState(() => _focused = _focus.hasFocus);

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: AppText.label),
          const SizedBox(height: AppSizes.sm),
        ],
        AnimatedContainer(
          duration: AppDurations.fast,
          curve: AppDurations.easeOut,
          height: AppSizes.fieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.md,
            border: Border.all(
              color: _focused ? AppColors.borderStrong : AppColors.border,
              width: _focused ? 1.6 : 1.2,
            ),
          ),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon,
                    size: 20,
                    color: _focused
                        ? AppColors.textPrimary
                        : AppColors.textTertiary),
                const SizedBox(width: AppSizes.md),
              ],
              if (widget.prefixText != null)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Text(widget.prefixText!, style: AppText.bodyStrong),
                ),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  obscureText: widget.obscure,
                  keyboardType: widget.keyboardType,
                  inputFormatters: widget.inputFormatters,
                  textInputAction: widget.textInputAction,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  cursorColor: AppColors.ink,
                  style: AppText.bodyStrong,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: widget.hint,
                    hintStyle: AppText.body.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: AppSizes.sm),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
