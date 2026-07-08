import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/error_messages.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../app_button.dart';

/// A single shimmering skeleton block. Compose several to mock a loading layout.
/// Defaults suit a light card (muted-grey bone, white shimmer sweep); pass
/// [color]/[highlightColor] to use the same block on a dark surface (e.g. a
/// premium/dark hero card) without it looking like a mistake.
class AppShimmerBox extends StatelessWidget {
  const AppShimmerBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius,
    this.color,
    this.highlightColor,
  });

  final double? width;
  final double height;
  final BorderRadius? radius;
  final Color? color;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color ?? AppColors.surfaceMuted,
            borderRadius: radius ?? AppRadii.sm,
          ),
        )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
          duration: 1200.ms,
          color: highlightColor ?? Colors.white.withValues(alpha: 0.55),
        );
  }
}

/// A friendly error panel with an optional Retry button. Used by [AsyncValueView]
/// and any screen that needs a full-bleed error state.
class ErrorRetryView extends StatelessWidget {
  const ErrorRetryView({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.cloud_off_rounded,
  });

  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.textTertiary),
            const SizedBox(height: AppSizes.md),
            Text(message, textAlign: TextAlign.center, style: AppText.body),
            if (onRetry != null) ...[
              const SizedBox(height: AppSizes.lg),
              AppButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                expand: false,
                variant: AppButtonVariant.outline,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ).animate().fadeIn(duration: 200.ms),
    );
  }
}

/// A calm empty-state placeholder.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_rounded,
  });

  final String title;
  final String? subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.textTertiary),
            const SizedBox(height: AppSizes.md),
            Text(title, textAlign: TextAlign.center, style: AppText.bodyStrong),
            if (subtitle != null) ...[
              const SizedBox(height: AppSizes.xs),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppText.caption,
              ),
            ],
          ],
        ),
      ).animate().fadeIn(duration: 200.ms),
    );
  }
}

/// Renders an [AsyncValue] as one of: loading (skeleton) / error (retry) /
/// empty / data. The single reusable bridge between Riverpod and the UI states
/// every data screen needs.
///
/// ```dart
/// AsyncValueView(
///   value: ref.watch(transactionsProvider),
///   onRetry: () => ref.invalidate(transactionsProvider),
///   isEmpty: (list) => list.isEmpty,
///   data: (list) => ListView.builder(...),
/// )
/// ```
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.loading,
    this.onRetry,
    this.isEmpty,
    this.empty,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final WidgetBuilder? loading;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;
  final WidgetBuilder? empty;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => loading?.call(context) ?? const _DefaultSkeleton(),
      error: (e, _) =>
          ErrorRetryView(message: friendlyError(e), onRetry: onRetry),
      data: (d) {
        if (isEmpty?.call(d) ?? false) {
          return empty?.call(context) ??
              const EmptyStateView(title: 'Nothing here yet');
        }
        return data(d);
      },
    );
  }
}

class _DefaultSkeleton extends StatelessWidget {
  const _DefaultSkeleton();

  @override
  Widget build(BuildContext context) {
    // A fixed-length Column, not a ListView: this skeleton is almost always
    // used as `AsyncValueView`'s body inside `AppScaffold`'s default scrollable
    // SingleChildScrollView, which gives its child unbounded height. A sliver
    // viewport (ListView) can't lay out under unbounded height and crashes
    // with "RenderViewport was not laid out" — a plain Column has no such
    // constraint and doesn't need to scroll itself (the six items already fit,
    // and the parent scroll view handles overflow).
    return Padding(
      padding: const EdgeInsets.all(AppSizes.screenPad),
      child: Column(
        children: List.generate(
          6,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: AppSizes.md),
            child: AppShimmerBox(height: 76, radius: null),
          ),
        ),
      ),
    );
  }
}
