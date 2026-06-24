import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_sizes.dart';
import '../core/theme/app_typography.dart';

/// Transaction PIN field — shows masked dots with a "Show" toggle, matching the
/// sign-in mockup. Backed by a hidden [TextField] so the keyboard works.
class PinField extends StatefulWidget {
  const PinField({
    super.key,
    required this.controller,
    this.length = 4,
    this.onChanged,
    this.onCompleted,
  });

  final TextEditingController controller;
  final int length;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;

  @override
  State<PinField> createState() => _PinFieldState();
}

class _PinFieldState extends State<PinField> {
  final FocusNode _focus = FocusNode();
  bool _obscure = true;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;
    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppDurations.fast,
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
            Icon(Icons.lock_outline_rounded,
                size: 20,
                color: _focused ? AppColors.textPrimary : AppColors.textTertiary),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // The visible dots / digits.
                  _obscure
                      ? Row(
                          children: List.generate(
                            value.length.clamp(0, widget.length),
                            (_) => const Padding(
                              padding: EdgeInsets.only(right: 10),
                              child: _Dot(),
                            ),
                          ),
                        )
                      : Text(value, style: AppText.bodyStrong.copyWith(
                          letterSpacing: 6)),
                  if (value.isEmpty && !_focused)
                    Text('Enter PIN',
                        style: AppText.body
                            .copyWith(color: AppColors.textTertiary)),
                  // Hidden real input.
                  Opacity(
                    opacity: 0,
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focus,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: widget.length,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(widget.length),
                      ],
                      onChanged: (v) {
                        setState(() {});
                        widget.onChanged?.call(v);
                        if (v.length == widget.length) {
                          widget.onCompleted?.call(v);
                        }
                      },
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _obscure = !_obscure),
              child: Text(
                _obscure ? 'Show' : 'Hide',
                style: AppText.label.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: const BoxDecoration(
        color: AppColors.textPrimary,
        shape: BoxShape.circle,
      ),
    );
  }
}
