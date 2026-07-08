import 'package:flutter/material.dart';
import '../core/theme/app_accent.dart';

/// A refresh icon that spins **only while a fetch is in flight**, then stops.
///
/// Drive it from whatever loading signal the screen already has —
/// `someAsync.isLoading` from a provider, or a local `_isRefreshing` bool if
/// none exists. When [isLoading] is true the icon rotates continuously; when it
/// flips back to false the spin finishes its current turn and stops (it never
/// animates forever while idle).
///
/// Two flavours share one animation:
///  * [AnimatedRefreshIcon] — the bare rotating glyph, for inline placements
///    (e.g. a "Refresh" affordance on a coloured card).
///  * [AnimatedRefreshIconButton] — the same glyph inside the app's standard
///    tappable icon chip; taps are ignored while [isLoading] so a refresh can't
///    be fired twice.
class AnimatedRefreshIcon extends StatefulWidget {
  const AnimatedRefreshIcon({
    super.key,
    required this.isLoading,
    this.icon = Icons.refresh_rounded,
    this.size = 20,
    this.color,
  });

  final bool isLoading;
  final IconData icon;
  final double size;
  final Color? color;

  @override
  State<AnimatedRefreshIcon> createState() => _AnimatedRefreshIconState();
}

class _AnimatedRefreshIconState extends State<AnimatedRefreshIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  /// Tracks whether we're in continuous-spin mode, independent of the
  /// controller's transient `isAnimating` (which is also true during the brief
  /// "finish the turn" stop). This keeps a rapid loading→idle→loading flip from
  /// leaving the icon stalled mid-turn.
  bool _spinning = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(AnimatedRefreshIcon old) {
    super.didUpdateWidget(old);
    if (widget.isLoading != old.isLoading) _sync();
  }

  void _sync() {
    if (widget.isLoading && !_spinning) {
      _spinning = true;
      _controller.repeat();
    } else if (!widget.isLoading && _spinning) {
      _spinning = false;
      // Let the current rotation finish for a smooth stop, then hold at rest —
      // unless a new fetch has already re-started the spin in the meantime.
      _controller
          .animateTo(1, duration: const Duration(milliseconds: 300))
          .then((_) {
            if (mounted && !_spinning) _controller.value = 0;
          });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(widget.icon, size: widget.size, color: widget.color),
    );
  }
}

/// The standard tappable refresh chip (matches [AppIconButton]'s look) whose
/// glyph spins while [isLoading]. Tapping is disabled during a fetch so the
/// user can't queue duplicate refreshes.
class AnimatedRefreshIconButton extends StatelessWidget {
  const AnimatedRefreshIconButton({
    super.key,
    required this.isLoading,
    required this.onPressed,
    this.icon = Icons.refresh_rounded,
    this.background,
    this.iconColor,
    this.size = 40,
    this.tooltip,
  });

  final bool isLoading;
  final VoidCallback onPressed;
  final IconData icon;

  /// Null → themed accent tint, matching [AppIconButton].
  final Color? background;
  final Color? iconColor;
  final double size;

  /// Optional long-press/hover hint (e.g. "Refresh").
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    final bg = background ?? accent.accentSoft;
    final fg = iconColor ?? accent.onAccentSoft;
    final radius = BorderRadius.circular(size * 0.32);
    final button = Material(
      color: bg,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Disabled while loading → no duplicate fetches from repeated taps.
        onTap: isLoading ? null : onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: AnimatedRefreshIcon(
              isLoading: isLoading,
              icon: icon,
              size: size * 0.46,
              color: fg,
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
