import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Wraps the app and plays a gentle **cross-dissolve** when the theme changes:
/// the previous frame is snapshotted, the new theme is applied beneath it, and
/// the snapshot fades away — so the whole screen softly melts from the old
/// theme into the new one. Calm and familiar (the most user-friendly option).
///
/// Fully defensive — if a snapshot can't be captured it just applies the
/// change with no animation, so it can never break the app.
class ThemeReveal extends StatefulWidget {
  const ThemeReveal({super.key, required this.child});

  final Widget child;

  static ThemeRevealState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<ThemeRevealState>();

  @override
  State<ThemeReveal> createState() => ThemeRevealState();
}

class ThemeRevealState extends State<ThemeReveal>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundaryKey = GlobalKey();
  late final AnimationController _controller;
  late final Animation<double> _fade;

  ui.Image? _snapshot;
  Size _snapshotSize = Size.zero;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  /// Snapshot the screen, apply [apply] beneath it, then cross-dissolve.
  Future<void> play({required VoidCallback apply}) async {
    if (_running) {
      apply();
      return;
    }
    _running = true;
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null || !boundary.hasSize) {
        apply();
        return;
      }
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final image = await boundary.toImage(pixelRatio: dpr);
      if (!mounted) {
        image.dispose();
        apply();
        return;
      }
      setState(() {
        _snapshot = image;
        _snapshotSize = boundary.size;
      });
      apply(); // new theme renders beneath the snapshot
      await _controller.forward(from: 0); // fade the old snapshot out
    } catch (_) {
      apply();
    } finally {
      final old = _snapshot;
      if (mounted) setState(() => _snapshot = null);
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RepaintBoundary(key: _boundaryKey, child: widget.child),
        if (_snapshot != null)
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                // 1 → 0 so the old theme dissolves into the new one beneath.
                opacity: ReverseAnimation(_fade),
                child: RawImage(
                  image: _snapshot,
                  width: _snapshotSize.width,
                  height: _snapshotSize.height,
                  fit: BoxFit.fill,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
