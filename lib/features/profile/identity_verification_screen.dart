import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../auth/application/auth_controller.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_loaders.dart';
import '../../widgets/feedback/app_snackbar.dart';

/// Mutable draft carried through the KYC steps (doc type + 3 captured images).
class KycDraft {
  int? docIndex; // 0 NIN · 1 licence · 2 passport
  XFile? front;
  XFile? back;
  XFile? selfie;

  String get docType => switch (docIndex) {
    1 => 'drivers_license',
    2 => 'passport',
    _ => 'nin',
  };
  String get docLabel => switch (docIndex) {
    1 => "Driver's licence",
    2 => 'International passport',
    _ => 'National ID (NIN)',
  };

  /// Passports are single-sided (data page); other IDs need a back too.
  bool get needsBack => docType != 'passport';

  bool get documentsReady =>
      docIndex != null && front != null && (!needsBack || back != null);
}

/// Identity verification entry point. The backend's `identity.status` is the
/// only source of truth for what's shown here — never faked/hardcoded:
/// - `verified` → [_VerifiedIdentityView], no way to restart the flow.
/// - `pending` → [_PendingIdentityView], no way to restart (no resubmission
///   endpoint while a review is in flight).
/// - `rejected` → [_RejectedIdentityView], with "Update Documents" — the
///   backend's submit endpoint doesn't block resubmission after a rejection.
/// - `unverified` (or anything else) → [_StartVerificationView] (mockup 7).
class IdentityVerificationScreen extends ConsumerStatefulWidget {
  const IdentityVerificationScreen({super.key});

  @override
  ConsumerState<IdentityVerificationScreen> createState() =>
      _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState
    extends ConsumerState<IdentityVerificationScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Always refetches on open (rather than trusting a possibly-stale cached
  /// profile) so a status that changed server-side — e.g. a review that
  /// completed since this user last opened the app — is reflected here. A
  /// failure just falls back to whatever status was last known (see build())
  /// instead of blocking the screen — the snackbar is the only error signal.
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider.notifier).refreshProfile();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppSnackbar.error(context, friendlyError(e), onRetry: _load);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AppScaffold(
        title: 'Identity verification',
        scrollable: false,
        body: Center(child: AppCircularLoader()),
      );
    }

    final user = ref.watch(authControllerProvider).valueOrNull?.user;
    return switch (user?.identityStatus) {
      'verified' => _VerifiedIdentityView(reviewedAt: user?.identityReviewedAt),
      'pending' => const _PendingIdentityView(),
      'rejected' => _RejectedIdentityView(
        reason: user?.identityRejectionReason,
      ),
      _ => const _StartVerificationView(),
    };
  }
}

/// The original "start verification" intro (mockup 7) — shown only when
/// `identityStatus` is `unverified` (or unknown).
class _StartVerificationView extends StatelessWidget {
  const _StartVerificationView();

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return AppScaffold(
      title: 'Identity verification',
      bottomAction: AppButton(
        label: 'Start verification',
        trailingIcon: Icons.arrow_forward_rounded,
        onPressed: () =>
            AppNav.push(context, ChooseDocumentScreen(draft: KycDraft())),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          AppCard(
            color: accent.isLime
                ? const Color(0xFFE2DDF8)
                : AppColors.surfaceMuted,
            padding: const EdgeInsets.all(AppSizes.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: AppRadii.md,
                  ),
                  child: Icon(
                    Icons.verified_outlined,
                    color: accent.isLime
                        ? const Color(0xFFCBF24A)
                        : AppColors.textOnDark,
                    size: 26,
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
                Text('Get the HTP Verified badge', style: AppText.h2),
                const SizedBox(height: AppSizes.sm),
                Text(
                  'Verified accounts win more buyers, unlock higher transaction '
                  'limits, and rank higher in trust scores.',
                  style: AppText.body,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.xl),
          const SectionLabel("You'll need"),
          const SizedBox(height: AppSizes.md),
          _RequirementCard(
            icon: Icons.badge_outlined,
            title: 'A valid government ID',
            subtitle: 'Front & back, clearly photographed',
            iconBg: accent.isLime ? const Color(0xFFD0EEDB) : null,
          ),
          const SizedBox(height: AppSizes.md),
          const _RequirementCard(
            icon: Icons.camera_alt_outlined,
            title: 'A quick selfie',
            subtitle: 'To match your face to the ID',
          ),
        ],
      ),
    );
  }
}

/// Shown when `identityStatus == 'verified'` — informational only, no way to
/// restart the flow.
class _VerifiedIdentityView extends StatelessWidget {
  const _VerifiedIdentityView({this.reviewedAt});
  final DateTime? reviewedAt;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    final circle = accent.isLime ? accent.accent : AppColors.ink;
    final onCircle = accent.isLime ? accent.onAccent : AppColors.textOnDark;
    return AppScaffold(
      title: 'Identity verification',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSizes.xl),
          Center(
            child: Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: circle,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: circle.withValues(alpha: 0.45),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(Icons.verified_rounded, size: 40, color: onCircle),
            ),
          ),
          const SizedBox(height: AppSizes.xl),
          Text(
            'Identity Verified',
            textAlign: TextAlign.center,
            style: AppText.h1,
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            'Your identity verification is complete.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.xl),
          AppCard(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.isLime
                        ? const Color(0xFFD0EEDB)
                        : AppColors.surfaceMuted,
                    borderRadius: AppRadii.sm,
                  ),
                  child: const Icon(
                    Icons.verified_outlined,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('HTP Verified badge', style: AppText.bodyStrong),
                      const SizedBox(height: 2),
                      Text(
                        reviewedAt != null
                            ? 'Verified ${Dates.medium(reviewedAt!)}'
                            : 'Your account is fully verified',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                const StatusPill(
                  label: 'Verified',
                  icon: Icons.check_rounded,
                  background: AppColors.successSoft,
                  foreground: AppColors.success,
                  dense: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when `identityStatus == 'pending'` — no restart affordance; the
/// backend has no resubmission path while a review is already in flight.
class _PendingIdentityView extends StatelessWidget {
  const _PendingIdentityView();

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return AppScaffold(
      title: 'Identity verification',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSizes.xl),
          Center(
            child: Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.schedule_rounded,
                size: 38,
                color: AppColors.warning,
              ),
            ),
          ),
          const SizedBox(height: AppSizes.xl),
          Text(
            'Verification under review',
            textAlign: TextAlign.center,
            style: AppText.h1,
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            'We will notify you once approved.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.xl),
          AppCard(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.isLime
                        ? const Color(0xFFF7EBB0)
                        : AppColors.surfaceMuted,
                    borderRadius: AppRadii.sm,
                  ),
                  child: const Icon(
                    Icons.hourglass_top_rounded,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status: Pending', style: AppText.bodyStrong),
                      const SizedBox(height: 2),
                      Text(
                        'Documents received, awaiting review',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                StatusPill(
                  label: 'In review',
                  icon: Icons.refresh_rounded,
                  background: accent.isLime
                      ? const Color(0xFFFBF2C6)
                      : AppColors.surfaceMuted,
                  dense: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when `identityStatus == 'rejected'` — offers "Update Documents",
/// which resubmits (the backend's `/me/identity` endpoint allows resubmission
/// after a rejection; it only blocks nothing explicitly, but the product
/// intent is: rejected → may retry, pending → may not).
class _RejectedIdentityView extends StatelessWidget {
  const _RejectedIdentityView({this.reason});
  final String? reason;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Identity verification',
      bottomAction: AppButton(
        label: 'Update Documents',
        icon: Icons.upload_outlined,
        trailingIcon: Icons.arrow_forward_rounded,
        onPressed: () =>
            AppNav.push(context, ChooseDocumentScreen(draft: KycDraft())),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSizes.xl),
          Center(
            child: Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.gpp_maybe_outlined,
                size: 38,
                color: AppColors.danger,
              ),
            ),
          ),
          const SizedBox(height: AppSizes.xl),
          Text(
            'Verification rejected',
            textAlign: TextAlign.center,
            style: AppText.h1,
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            (reason != null && reason!.trim().isNotEmpty)
                ? reason!.trim()
                : 'Verification was rejected. Please update your documents.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
        ],
      ),
    );
  }
}

/// Step 1 — pick an ID type, then capture FRONT + BACK photos.
class ChooseDocumentScreen extends StatefulWidget {
  const ChooseDocumentScreen({super.key, required this.draft});
  final KycDraft draft;

  @override
  State<ChooseDocumentScreen> createState() => _ChooseDocumentScreenState();
}

class _DocOptionData {
  const _DocOptionData(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _ChooseDocumentScreenState extends State<ChooseDocumentScreen> {
  final _picker = ImagePicker();

  static const _docs = [
    _DocOptionData('National ID (NIN)', Icons.person_outline_rounded),
    _DocOptionData('Driver\'s licence', Icons.directions_car_outlined),
    _DocOptionData('International passport', Icons.public_outlined),
  ];

  KycDraft get _d => widget.draft;

  Future<void> _pick({required bool front}) async {
    final f = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (f != null && mounted) {
      setState(() => front ? _d.front = f : _d.back = f);
    }
  }

  void _continue() => AppNav.push(context, TakeSelfieScreen(draft: _d));

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return AppScaffold(
      title: 'Identity verification',
      stepTrailing: Text('1 / 3', style: AppText.caption),
      bottomAction: AppButton(
        label: 'Continue',
        trailingIcon: Icons.arrow_forward_rounded,
        enabled: _d.documentsReady,
        onPressed: _continue,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          Text('Choose a document', style: AppText.h1),
          const SizedBox(height: AppSizes.xs),
          Text(
            'Select the ID type, then add clear photos.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.lg),
          for (int i = 0; i < _docs.length; i++) ...[
            _DocOption(
              data: _docs[i],
              selected: _d.docIndex == i,
              accent: accent,
              onTap: () => setState(() => _d.docIndex = i),
            ),
            if (i != _docs.length - 1) const SizedBox(height: AppSizes.md),
          ],
          if (_d.docIndex != null) ...[
            const SizedBox(height: AppSizes.xl),
            SectionLabel('Upload ${_docs[_d.docIndex!].label}'),
            const SizedBox(height: AppSizes.md),
            _UploadBox(
              label: _d.needsBack ? 'Front of document' : 'Photo page',
              file: _d.front,
              onTap: () => _pick(front: true),
            ),
            if (_d.needsBack) ...[
              const SizedBox(height: AppSizes.md),
              _UploadBox(
                label: 'Back of document',
                file: _d.back,
                onTap: () => _pick(front: false),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A labelled dashed upload area showing the picked image (or a prompt).
class _UploadBox extends StatelessWidget {
  const _UploadBox({
    required this.label,
    required this.file,
    required this.onTap,
  });
  final String label;
  final XFile? file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: AppText.label),
            const Spacer(),
            if (file != null)
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 14,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Added',
                    style: AppText.caption.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DottedBorderBox(
            fill: AppColors.surfaceMuted,
            active: file != null,
            child: SizedBox(
              height: 150,
              width: double.infinity,
              child: file != null
                  ? _PickedImage(file: file!)
                  : const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_a_photo_outlined,
                            size: 28,
                            color: AppColors.textTertiary,
                          ),
                          SizedBox(height: 8),
                          Text('Tap to add photo', style: AppText.caption),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DocOption extends StatelessWidget {
  const _DocOption({
    required this.data,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final _DocOptionData data;
  final bool selected;
  final AppAccent accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tileColor = selected
        ? (accent.isLime ? const Color(0xFFCBF24A) : AppColors.ink)
        : (accent.isLime ? const Color(0xFFECE9FB) : AppColors.surfaceMuted);
    final iconColor = selected
        ? (accent.isLime ? AppColors.textPrimary : AppColors.textOnDark)
        : AppColors.textPrimary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AppCard(
        border: selected
            ? Border.all(color: AppColors.borderStrong, width: 1.6)
            : null,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tileColor,
                borderRadius: AppRadii.sm,
              ),
              child: Icon(data.icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(child: Text(data.label, style: AppText.bodyStrong)),
            _Radio(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? AppColors.ink : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.ink : AppColors.border,
          width: 1.6,
        ),
      ),
      child: selected
          ? const Icon(
              Icons.check_rounded,
              size: 14,
              color: AppColors.textOnDark,
            )
          : null,
    );
  }
}

class _RequirementCard extends StatelessWidget {
  const _RequirementCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconBg,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconBg;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBg ?? AppColors.surfaceMuted,
              borderRadius: AppRadii.sm,
            ),
            child: Icon(icon, size: 22, color: AppColors.textPrimary),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(subtitle, style: AppText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 2 — capture a selfie.
class TakeSelfieScreen extends StatefulWidget {
  const TakeSelfieScreen({super.key, required this.draft});
  final KycDraft draft;

  @override
  State<TakeSelfieScreen> createState() => _TakeSelfieScreenState();
}

class _TakeSelfieScreenState extends State<TakeSelfieScreen> {
  final _picker = ImagePicker();

  Future<void> _pickSelfie() async {
    final f = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (f != null && mounted) setState(() => widget.draft.selfie = f);
  }

  void _continue() =>
      AppNav.push(context, ReviewSubmitScreen(draft: widget.draft));

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Identity verification',
      stepTrailing: Text('2 / 3', style: AppText.caption),
      bottomAction: AppButton(
        label: 'Continue',
        trailingIcon: Icons.arrow_forward_rounded,
        enabled: widget.draft.selfie != null,
        onPressed: _continue,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: AppSizes.sm),
          Text('Take a selfie', style: AppText.h1, textAlign: TextAlign.center),
          const SizedBox(height: AppSizes.xs),
          Text(
            'Position your face in the circle. Make sure you\'re in good lighting.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.xl),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pickSelfie,
            child: _SelfieCircle(file: widget.draft.selfie),
          ),
          const SizedBox(height: AppSizes.xl),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SelfieCheck(label: 'Face forward'),
              _SelfieCheck(label: 'Remove glasses'),
              _SelfieCheck(label: 'Good light'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelfieCircle extends StatelessWidget {
  const _SelfieCircle({this.file});
  final XFile? file;

  @override
  Widget build(BuildContext context) {
    final added = file != null;
    return SizedBox(
      width: 200,
      height: 200,
      child: CustomPaint(
        painter: _DashedCirclePainter(
          color: added ? AppColors.success : AppColors.border,
        ),
        child: added
            ? Padding(
                padding: const EdgeInsets.all(6),
                child: ClipOval(child: _PickedImage(file: file!)),
              )
            : const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      size: 30,
                      color: AppColors.textTertiary,
                    ),
                    SizedBox(height: 8),
                    Text('Add selfie', style: AppText.caption),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Loads an [XFile]'s bytes once and renders it (works on mobile + web).
class _PickedImage extends StatefulWidget {
  const _PickedImage({required this.file});
  final XFile file;

  @override
  State<_PickedImage> createState() => _PickedImageState();
}

class _PickedImageState extends State<_PickedImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_PickedImage old) {
    super.didUpdateWidget(old);
    if (old.file.path != widget.file.path) _load();
  }

  Future<void> _load() async {
    final b = await widget.file.readAsBytes();
    if (mounted) setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (b == null) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Image.memory(
      b,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      center,
      size.width / 2,
      Paint()..color = AppColors.surfaceMuted.withValues(alpha: 0.4),
    );

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: size.width / 2));
    const dash = 0.5;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        canvas.drawPath(metric.extractPath(dist, dist + dash), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) => old.color != color;
}

class _SelfieCheck extends StatelessWidget {
  const _SelfieCheck({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.successSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 16,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: AppText.caption),
      ],
    );
  }
}

/// Step 3 — review the captured documents, upload + submit for review.
class ReviewSubmitScreen extends ConsumerStatefulWidget {
  const ReviewSubmitScreen({super.key, required this.draft});
  final KycDraft draft;

  @override
  ConsumerState<ReviewSubmitScreen> createState() => _ReviewSubmitScreenState();
}

class _ReviewSubmitScreenState extends ConsumerState<ReviewSubmitScreen> {
  bool _busy = false;

  Future<void> _submit() async {
    final d = widget.draft;
    setState(() => _busy = true);
    try {
      final upload = ref.read(uploadRepositoryProvider);
      final frontUrl = await upload.uploadImage(d.front!.path);
      final backUrl = d.back != null
          ? await upload.uploadImage(d.back!.path)
          : null;
      final selfieUrl = await upload.uploadImage(d.selfie!.path);
      await ref
          .read(authControllerProvider.notifier)
          .submitIdentity(
            docType: d.docType,
            documentFrontUrl: frontUrl,
            documentBackUrl: backUrl,
            selfieUrl: selfieUrl,
          );
      if (!mounted) return;
      AppNav.push(context, SubmittedForReviewScreen(docLabel: d.docLabel));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        AppSnackbar.error(context, e.userMessage);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        AppSnackbar.error(context, 'Upload failed. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    final d = widget.draft;
    return AppScaffold(
      title: 'Identity verification',
      stepTrailing: Text('3 / 3', style: AppText.caption),
      bottomAction: AppButton(
        label: 'Submit for verification',
        icon: Icons.verified_outlined,
        accentInLime: true,
        loading: _busy,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          Text('Review & submit', style: AppText.h1),
          const SizedBox(height: AppSizes.xs),
          Text(
            'Confirm everything is clear and readable before submitting.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.lg),
          _ReviewRow(
            title: '${d.docLabel} — front',
            file: d.front,
            tile: accent.isLime
                ? const Color(0xFFD0EEDB)
                : AppColors.surfaceMuted,
          ),
          if (d.back != null) ...[
            const SizedBox(height: AppSizes.md),
            _ReviewRow(
              title: '${d.docLabel} — back',
              file: d.back,
              tile: accent.isLime
                  ? const Color(0xFFD0EEDB)
                  : AppColors.surfaceMuted,
            ),
          ],
          const SizedBox(height: AppSizes.md),
          _ReviewRow(
            title: 'Selfie',
            file: d.selfie,
            tile: accent.isLime
                ? const Color(0xFFF7EBB0)
                : AppColors.surfaceMuted,
          ),
          const SizedBox(height: AppSizes.md),
          Container(
            padding: const EdgeInsets.all(AppSizes.md),
            decoration: BoxDecoration(
              color: accent.isLime
                  ? const Color(0xFFF7EFD6)
                  : AppColors.surfaceMuted,
              borderRadius: AppRadii.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    'By submitting you confirm these documents are genuine and '
                    'belong to you.',
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.title,
    required this.file,
    required this.tile,
  });

  final String title;
  final XFile? file;
  final Color tile;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppRadii.sm,
            child: Container(
              width: 48,
              height: 48,
              color: tile,
              child: file != null
                  ? _PickedImage(file: file!)
                  : const Icon(Icons.image_outlined, size: 22),
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  'Captured',
                  style: AppText.caption.copyWith(color: AppColors.success),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 22,
            color: AppColors.success,
          ),
        ],
      ),
    );
  }
}

/// Submitted-for-review confirmation. Identity is now genuinely `pending`.
class SubmittedForReviewScreen extends StatelessWidget {
  const SubmittedForReviewScreen({super.key, required this.docLabel});
  final String docLabel;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    final circle = accent.isLime ? accent.accent : AppColors.ink;
    final onCircle = accent.isLime ? accent.onAccent : AppColors.textOnDark;

    return AppScaffold(
      title: 'Verification',
      bottomAction: AppButton(
        label: 'Back to profile',
        trailingIcon: Icons.arrow_forward_rounded,
        onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSizes.xl),
          Center(
            child: Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: circle,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: circle.withValues(alpha: 0.45),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(Icons.verified_rounded, size: 40, color: onCircle),
            ),
          ),
          const SizedBox(height: AppSizes.xl),
          Text(
            'Submitted for review',
            textAlign: TextAlign.center,
            style: AppText.h1,
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            'We\'re reviewing your documents. Most verifications complete within '
            'a few minutes — we\'ll notify you.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.xl),
          AppCard(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.isLime
                        ? const Color(0xFFF7EBB0)
                        : AppColors.surfaceMuted,
                    borderRadius: AppRadii.sm,
                  ),
                  child: const Icon(
                    Icons.schedule_rounded,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status: Pending', style: AppText.bodyStrong),
                      const SizedBox(height: 2),
                      Text(
                        '$docLabel + selfie received',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                StatusPill(
                  label: 'In review',
                  icon: Icons.refresh_rounded,
                  background: accent.isLime
                      ? const Color(0xFFFBF2C6)
                      : AppColors.surfaceMuted,
                  dense: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
