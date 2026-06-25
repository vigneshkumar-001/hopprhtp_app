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
    this.focusNode,
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

  /// Optional external focus node (e.g. to programmatically focus the field).
  final FocusNode? focusNode;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final bool _ownsFocus = widget.focusNode == null;
  late final FocusNode _focus =
      (widget.focusNode ?? FocusNode())..addListener(_onFocus);
  bool _focused = false;

  void _onFocus() => setState(() => _focused = _focus.hasFocus);

  /// Default keyboard-action behaviour when a screen doesn't supply its own:
  /// the "Next" action jumps to the following field, anything else dismisses
  /// the keyboard. Gives the whole app field-to-field keyboard navigation.
  void _defaultSubmit(String _) {
    final action = widget.textInputAction ?? TextInputAction.next;
    if (action == TextInputAction.next) {
      FocusScope.of(context).nextFocus();
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    if (_ownsFocus) _focus.dispose();
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
                  // Default to a "Next" action so the keyboard shows a next
                  // button that walks through the form's fields in order.
                  textInputAction:
                      widget.textInputAction ?? TextInputAction.next,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted ?? _defaultSubmit,
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
