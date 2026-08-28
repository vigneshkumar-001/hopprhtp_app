import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../core/theme/app_colors.dart';

/// Five-star row. Read-only (display) when [onChanged] is null — used for
/// an existing rating or an average (which can be fractional, e.g. a 4.3
/// average renders a half-filled 4th star). Interactive (tap to pick 1-5,
/// always a whole number) when [onChanged] is supplied — used in the "Rate
/// your experience" sheet.
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 22,
    this.color = AppColors.warning,
  });

  final double value;
  final ValueChanged<int>? onChanged;
  final double size;
  final Color color;

  bool get _interactive => onChanged != null;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 5; i++)
          Padding(
            padding: EdgeInsets.only(right: i == 5 ? 0 : size * 0.12),
            child: GestureDetector(
              onTap: _interactive
                  ? () {
                      HapticFeedback.selectionClick();
                      onChanged!(i);
                    }
                  : null,
              child: Icon(_iconFor(i), size: size, color: _colorFor(i)),
            ),
          ),
      ],
    );
  }

  Color _colorFor(int i) => value >= i - 0.5 ? color : AppColors.border;

  IconData _iconFor(int i) {
    if (value >= i) return Icons.star_rounded;
    if (value >= i - 0.5) return Icons.star_half_rounded;
    return Icons.star_border_rounded;
  }
}
