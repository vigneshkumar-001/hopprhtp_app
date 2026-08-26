import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/connectivity.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';

/// A slim, persistent banner announcing when the device has no network
/// connection — the "real world app" pattern (WhatsApp, Instagram) of
/// always making offline state visible, not just at the moment some action
/// happens to fail. Slides down from the top the instant connectivity
/// drops, and back up the instant it's restored.
///
/// Mount this once, high in the widget tree (see HopprApp's builder), so
/// it overlays every screen automatically — no per-screen wiring needed.
class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Treat "unknown" (stream hasn't emitted yet) as online — matches
    // ConnectivityRef.isOnline's own optimistic default, so this banner
    // never flashes on for a moment on cold start before the first real
    // reading arrives.
    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? true;

    return IgnorePointer(
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        offset: isOnline ? const Offset(0, -1) : Offset.zero,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isOnline ? 0 : 1,
          child: Material(
            color: AppColors.danger,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.md,
                  vertical: AppSizes.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                    const SizedBox(width: AppSizes.xs),
                    Text(
                      'No internet connection',
                      style: AppText.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
