import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/dto/delivery_verification_status_dto.dart';
import '../../data/models/models.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/state_views.dart';
import '../../widgets/number_keypad.dart';
import '../../widgets/segmented_control.dart' show MapBackdrop;
import 'application/transactions_provider.dart';
import 'delivery_confirmed_screen.dart';

enum _Phase { locked, locating, inZone }

/// Confirm delivery — the original locked → locating → inside-zone UI, now
/// driven by the REAL backend. The phase comes from
/// [deliveryVerificationStatusProvider] (200m geofence, computed server-side);
/// the keypad only unlocks when the backend says the seller is in range; the
/// entered code is verified by the real `confirmDelivery` endpoint (OTP hash /
/// expiry / attempt-lockout all enforced there). Nothing here fakes success or
/// hardcodes a code — the seller asks the buyer to read it out.
class ConfirmDeliveryScreen extends ConsumerStatefulWidget {
  const ConfirmDeliveryScreen({super.key, required this.draft});
  final PaymentDraft draft;

  @override
  ConsumerState<ConfirmDeliveryScreen> createState() =>
      _ConfirmDeliveryScreenState();
}

class _ConfirmDeliveryScreenState extends ConsumerState<ConfirmDeliveryScreen> {
  static const _len = 6;
  String _otp = '';
  bool _busy = false; // refreshing device location / re-checking the zone
  bool _submitting = false;

  String? get _txId => widget.draft.transactionId;

  _Phase _phaseFor(DeliveryVerificationStatus? status) {
    if (_busy || status == null) return _Phase.locating;
    return status.canVerify ? _Phase.inZone : _Phase.locked;
  }

  /// "Simulate moving into the zone" → in reality this refreshes the seller's
  /// device location, pushes it to the backend, and re-checks the 200m
  /// eligibility. If the seller is genuinely within range the code field
  /// unlocks; otherwise it stays locked. No faking.
  Future<void> _refreshZone() async {
    final txId = _txId;
    if (txId == null || _busy) return;
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    await _updateLocationBestEffort(txId);
    if (!mounted) return;
    ref.invalidate(deliveryVerificationStatusProvider(txId));
    setState(() => _busy = false);
  }

  Future<void> _updateLocationBestEffort(String txId) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await ref
          .read(transactionRepositoryProvider)
          .updateDeliveryLocation(
            txId,
            latitude: pos.latitude,
            longitude: pos.longitude,
          );
    } catch (_) {
      // Best-effort — the re-check falls back to the last known backend
      // location if the device position can't be captured.
    }
  }

  void _digit(String d, DeliveryVerificationStatus? status) {
    if (_phaseFor(status) != _Phase.inZone ||
        _submitting ||
        _otp.length >= _len) {
      return;
    }
    setState(() => _otp += d);
    if (_otp.length == _len) _submit(status);
  }

  void _back() {
    if (_otp.isEmpty || _submitting) return;
    setState(() => _otp = _otp.substring(0, _otp.length - 1));
  }

  Future<void> _submit(DeliveryVerificationStatus? status) async {
    final txId = _txId;
    if (txId == null ||
        _submitting ||
        _phaseFor(status) != _Phase.inZone ||
        _otp.length < _len) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(transactionRepositoryProvider)
          .confirmDelivery(txId, otp: _otp);
      if (!mounted) return;
      // Real state changed — refresh everything that could now be stale.
      ref.invalidate(transactionDetailProvider(txId));
      ref.invalidate(transactionsProvider);
      ref.invalidate(trackingProvider(txId));
      // Delivery is confirmed — the buyer's delivery-code card must stop
      // showing (the code is now consumed/cleared server-side). Invalidating
      // it here covers the same-session case; a still-open buyer screen on a
      // different device re-syncs on its own app-resume/pull-to-refresh.
      ref.invalidate(deliveryCodeProvider(txId));
      ref.invalidate(transactionLedgerProvider(txId));
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(walletLedgerProvider);
      // Replace (never push) so this OTP/dispatch-code screen is removed from
      // the stack immediately — otherwise it would still be reachable via
      // back navigation from Delivery Confirmed.
      Navigator.of(context).pushReplacement(
        AppNav.route(DeliveryConfirmedScreen(draft: widget.draft)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, e.userMessage);
      // Wrong/expired code or lockout — clear the entry and re-read eligibility.
      setState(() => _otp = '');
      ref.invalidate(deliveryVerificationStatusProvider(txId));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final txId = _txId;
    if (txId == null) {
      return AppScaffold(
        title: 'Confirm delivery',
        body: const ErrorRetryView(
          message:
              'Transaction reference is missing. Please go back and try again.',
        ),
      );
    }

    // Delivery-actor-only UI guard (the backend enforces it regardless) — the
    // self-delivering seller, or the assigned Hoppr dispatcher. Default allow
    // while the role is still unknown so the real actor is never blocked.
    final isDeliveryActor = ref
        .watch(trackingProvider(txId))
        .maybeWhen(data: (t) => t.isDeliveryActor, orElse: () => true);
    if (!isDeliveryActor) {
      return AppScaffold(
        title: 'Confirm delivery',
        body: const ErrorRetryView(
          message:
              'Only the seller or assigned dispatcher can verify delivery for this transaction.',
        ),
      );
    }

    final status = ref
        .watch(deliveryVerificationStatusProvider(txId))
        .valueOrNull;
    final phase = _phaseFor(status);
    final inZone = phase == _Phase.inZone;
    final locating = phase == _Phase.locating;

    return AppScaffold(
      title: 'Confirm delivery',
      scrollable: false,
      padding: EdgeInsets.zero,
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSizes.screenPad,
          AppSizes.sm,
          AppSizes.screenPad,
          AppSizes.lg + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: AppRadii.lg,
              child: Stack(
                children: [
                  const MapBackdrop(showGeofence: true, height: 128),
                  Positioned(
                    left: AppSizes.md,
                    bottom: AppSizes.md,
                    child: _MapPill(phase: phase),
                  ),
                  const Positioned(
                    right: AppSizes.md,
                    top: AppSizes.md,
                    child: StatusPill(label: 'geofence · 200m', dense: true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              inZone
                  ? "Enter the buyer's delivery code"
                  : locating
                  ? 'Locating you…'
                  : 'Move into the delivery zone',
              style: AppText.h1.copyWith(fontSize: 21),
            ),
            const SizedBox(height: AppSizes.xs),
            _Subtitle(phase: phase),
            const SizedBox(height: AppSizes.sm),
            Text(
              'Delivery is confirmed using OTP and location verification to '
              'protect both buyer and seller.',
              style: AppText.caption.copyWith(
                fontStyle: FontStyle.italic,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            _OtpRow(otp: _otp, length: _len, locked: !inZone),
            const SizedBox(height: AppSizes.md),
            if (!inZone) const _LockNote(),
            const Spacer(),
            const SizedBox(height: AppSizes.lg),
            Stack(
              alignment: Alignment.center,
              children: [
                if (inZone)
                  NumberKeypad(
                    enabled: !_submitting,
                    onDigit: (d) => _digit(d, status),
                    onBackspace: _back,
                  )
                else
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 2.6, sigmaY: 2.6),
                    child: NumberKeypad(
                      enabled: false,
                      onDigit: (_) {},
                      onBackspace: () {},
                    ),
                  ),
                if (locating || _submitting)
                  _LoadingPill(
                    label: _submitting
                        ? 'Confirming delivery…'
                        : 'Checking your location…',
                  )
                else if (!inZone)
                  AppButton(
                    label: 'Simulate moving into the zone',
                    icon: Icons.my_location_rounded,
                    expand: false,
                    onPressed: _refreshZone,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPill extends StatelessWidget {
  const _MapPill({required this.phase});
  final _Phase phase;

  @override
  Widget build(BuildContext context) {
    switch (phase) {
      case _Phase.inZone:
        return const StatusPill(
          label: 'Inside delivery zone',
          icon: Icons.check_circle,
          background: AppColors.surface,
          foreground: AppColors.success,
        );
      case _Phase.locating:
        final isLime = AppAccent.of(context).isLime;
        final ring = isLime ? const Color(0xFFCBF24A) : AppColors.ink;
        final onRing = isLime ? AppColors.textPrimary : AppColors.textOnDark;
        return Container(
          padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.pill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
                child: _SpinningIcon(color: onRing),
              ),
              const SizedBox(width: 8),
              Text(
                'Checking your location…',
                style: AppText.caption.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        );
      case _Phase.locked:
        final badge = AppAccent.of(context).isLime
            ? const Color(0xFFD9532F)
            : AppColors.ink;
        return Container(
          padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.pill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: badge, shape: BoxShape.circle),
                child: const Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: AppColors.textOnDark,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Outside delivery zone',
                style: AppText.caption.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.phase});
  final _Phase phase;

  @override
  Widget build(BuildContext context) {
    final style = AppText.body.copyWith(fontSize: 11.5, height: 1.5);
    switch (phase) {
      case _Phase.inZone:
        return Text(
          "Delivery can only be confirmed once the dispatcher is physically "
          "inside a tight radius of the buyer, and only with the 6-digit "
          "code the dispatcher provides to the buyer at that delivery point.",
          style: style,
        );
      case _Phase.locating:
        return Text(
          "Checking that you're at the delivery point before unlocking the code field.",
          style: style,
        );
      case _Phase.locked:
        return Text.rich(
          TextSpan(
            style: style,
            children: const [
              TextSpan(
                text: 'The code field stays locked until you are within the ',
              ),
              TextSpan(
                text: '200 m geofence of the buyer delivery address. ',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              TextSpan(
                text: 'Move to the location, then refresh to unlock it.',
              ),
            ],
          ),
        );
    }
  }
}

class _OtpRow extends StatelessWidget {
  const _OtpRow({
    required this.otp,
    required this.length,
    required this.locked,
  });
  final String otp;
  final int length;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: i == length - 1 ? 0 : AppSizes.sm,
              ),
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: locked ? AppColors.surfaceMuted : AppColors.surface,
                  borderRadius: AppRadii.md,
                  border: Border.all(
                    color: (!locked && i == otp.length)
                        ? AppColors.borderStrong
                        : AppColors.border,
                    width: (!locked && i == otp.length) ? 1.6 : 1.2,
                  ),
                ),
                child: i < otp.length
                    ? Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppColors.textPrimary,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// "Code field locked" note — text with a lock-icon tile on the left.
class _LockNote extends StatelessWidget {
  const _LockNote();

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadii.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.isLime ? const Color(0xFFD9532F) : AppColors.ink,
              borderRadius: AppRadii.sm,
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              size: 20,
              color: AppColors.textOnDark,
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppText.caption.copyWith(height: 1.4),
                children: const [
                  TextSpan(
                    text: 'Code field locked. ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text:
                        "Move inside the delivery geofence to unlock it — the code can't be entered from outside.",
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A sync icon that spins continuously (used in the "locating" map pill).
class _SpinningIcon extends StatefulWidget {
  const _SpinningIcon({required this.color});
  final Color color;

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _c,
      child: Icon(Icons.sync_rounded, size: 16, color: widget.color),
    );
  }
}

/// Disabled-looking pill with a spinner, shown while "locating"/confirming.
class _LoadingPill extends StatelessWidget {
  const _LoadingPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizes.buttonHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
      decoration: BoxDecoration(
        color: const Color(0xFF55585E),
        borderRadius: AppRadii.btn,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation(AppColors.textOnDark),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Text(label, style: AppText.button.copyWith(fontSize: 14)),
        ],
      ),
    );
  }
}
