import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_sizes.dart';
import '../core/theme/app_typography.dart';

/// Common segmented code input — a row of equal boxes backed by a single
/// hidden [TextField]. Used for the OTP and PIN steps so both share the exact
/// same font, sizing and focus styling as the rest of the app.
class BoxedCodeInput extends StatefulWidget {
  const BoxedCodeInput({
    super.key,
    required this.controller,
    this.length = 6,
    this.obscure = false,
    this.autofocus = true,
    this.autofillHints,
    this.onChanged,
    this.onCompleted,
    this.focusNode,
  });

  final TextEditingController controller;
  final int length;
  final bool obscure;
  final bool autofocus;

  /// e.g. `[AutofillHints.oneTimeCode]` so the OS offers the SMS code.
  final List<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;

  /// Optional external focus node so a parent can focus the field on demand
  /// (e.g. auto-focusing the OTP/PIN step of a wizard). When null, an internal
  /// node is created and disposed here.
  final FocusNode? focusNode;

  @override
  State<BoxedCodeInput> createState() => _BoxedCodeInputState();
}

class _BoxedCodeInputState extends State<BoxedCodeInput>
    with SingleTickerProviderStateMixin {
  late final bool _ownsFocus = widget.focusNode == null;
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat(reverse: true);
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _blink.dispose();
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;
    final activeIndex = _focused && value.length < widget.length
        ? value.length
        : -1;

    return Stack(
      children: [
        SizedBox(
          height: 56,
          child: Row(
            children: [
              for (int i = 0; i < widget.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: i == widget.length - 1 ? 0 : AppSizes.sm,
                    ),
                    child: _Box(
                      filled: i < value.length,
                      digit: i < value.length ? value[i] : '',
                      obscure: widget.obscure,
                      active: i == activeIndex,
                      blink: _blink,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Hidden, full-width field that captures input/taps.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              autofillHints: widget.autofillHints,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              showCursor: false,
              enableInteractiveSelection: false,
              maxLength: widget.length,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(widget.length),
              ],
              onChanged: (v) {
                setState(() {});
                widget.onChanged?.call(v);
                if (v.length == widget.length) widget.onCompleted?.call(v);
              },
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.filled,
    required this.digit,
    required this.obscure,
    required this.active,
    required this.blink,
  });

  final bool filled;
  final String digit;
  final bool obscure;
  final bool active;
  final Animation<double> blink;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (filled) {
      content = obscure
          ? Container(
              width: 11,
              height: 11,
              decoration: const BoxDecoration(
                color: AppColors.textPrimary,
                shape: BoxShape.circle,
              ),
            )
          : Text(digit, style: AppText.h2);
    } else if (active) {
      content = FadeTransition(
        opacity: blink,
        child: Container(width: 2, height: 24, color: AppColors.ink),
      );
    } else {
      content = const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: AppDurations.fast,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.md,
        border: Border.all(
          color: active ? AppColors.borderStrong : AppColors.border,
          width: active ? 1.6 : 1.2,
        ),
      ),
      child: content,
    );
  }
}
