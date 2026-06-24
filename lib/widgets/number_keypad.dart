import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../core/theme/app_colors.dart';
import '../core/theme/app_sizes.dart';
import '../core/theme/app_typography.dart';

/// Common numeric keypad used by "Enter Transaction Code" and the geofenced
/// OTP entry. Emits digit taps and backspace; can be disabled (greyed out).
class NumberKeypad extends StatelessWidget {
  const NumberKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    const keys = [
      '1', '2', '3', //
      '4', '5', '6', //
      '7', '8', '9', //
      '', '0', '<', //
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSizes.sm,
      crossAxisSpacing: AppSizes.sm,
      childAspectRatio: 2.3,
      children: [
        for (final k in keys)
          if (k.isEmpty)
            const SizedBox.shrink()
          else
            _Key(
              label: k,
              isBackspace: k == '<',
              enabled: enabled,
              onTap: () {
                if (!enabled) return;
                HapticFeedback.selectionClick();
                if (k == '<') {
                  onBackspace();
                } else {
                  onDigit(k);
                }
              },
            ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.onTap,
    required this.enabled,
    this.isBackspace = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool isBackspace;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.surface : AppColors.surfaceMuted;
    final fg = enabled ? AppColors.textPrimary : AppColors.textTertiary;
    return Material(
      color: color,
      borderRadius: AppRadii.md,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Center(
          child: isBackspace
              ? Icon(Icons.backspace_outlined, size: 20, color: fg)
              : Text(label,
                  style: AppText.h3.copyWith(color: fg, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
