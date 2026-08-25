import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
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
import '../../data/repositories/auth_repository.dart';
import '../auth/application/auth_controller.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_loaders.dart';
import '../../widgets/feedback/app_snackbar.dart';
import 'live_selfie_camera_screen.dart';

/// One government ID document within a KYC submission — which ID type, plus
/// its captured front (+ back unless a passport).
class KycDocSlot {
  KycDocSlot(this.docIndex);
  final int docIndex; // 0 NIN · 1 licence · 2 passport
  XFile? front;
  XFile? back;

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
  bool get ready => front != null && (!needsBack || back != null);
}

/// Mutable draft carried through the KYC steps. Two distinct documents are
/// required (a stronger identity signal than one — enforced both by
/// [ChooseDocumentScreen] and the backend's identityVerifySchema), plus one
/// selfie.
class KycDraft {
  /// Chosen ID types, in pick order — always 0 or 2 entries.
  /// [ChooseDocumentScreen] enforces the count before Continue unlocks; on
  /// Continue these are copied into [docs] for [CaptureDocumentsScreen].
  List<int> selectedDocIndexes = [];
  List<KycDocSlot> docs = [];
  XFile? selfie;

  bool get documentsReady => docs.length == 2 && docs.every((d) => d.ready);
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
      // An admin actively looking at the submission reads the same as
      // "pending" to the submitter — no action is expected from them either way.
      'pending' || 'under_review' => const _PendingIdentityView(),
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
            title: 'Two valid government IDs',
            subtitle: 'Any 2 types — front & back, clearly photographed',
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

/// Step 1 — pick exactly 2 different ID types (a stronger identity signal
/// than one). Tapping a 3rd option while 2 are already chosen just nudges
/// instead of swapping a selection out from under the user.
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
  static const _docs = [
    _DocOptionData('National ID (NIN)', Icons.person_outline_rounded),
    _DocOptionData('Driver\'s licence', Icons.directions_car_outlined),
    _DocOptionData('International passport', Icons.public_outlined),
  ];

  KycDraft get _d => widget.draft;

  void _toggle(int i) {
    final sel = _d.selectedDocIndexes;
    if (sel.contains(i)) {
      HapticFeedback.selectionClick();
      setState(() => sel.remove(i));
      return;
    }
    if (sel.length >= 2) {
      HapticFeedback.heavyImpact();
      AppSnackbar.warning(context, 'You can choose only 2 document types.');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => sel.add(i));
  }

  void _continue() {
    if (_d.selectedDocIndexes.length != 2) return;
    _d.docs
      ..clear()
      ..addAll(_d.selectedDocIndexes.map(KycDocSlot.new));
    AppNav.push(context, CaptureDocumentsScreen(draft: _d));
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    final count = _d.selectedDocIndexes.length;
    return AppScaffold(
      title: 'Identity verification',
      stepTrailing: Text('1 / 4', style: AppText.caption),
      bottomAction: AppButton(
        label: 'Continue',
        trailingIcon: Icons.arrow_forward_rounded,
        enabled: count == 2,
        onPressed: _continue,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text('Choose 2 documents', style: AppText.h1)),
              const SizedBox(width: AppSizes.sm),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _SelectionCounter(count: count),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            'Pick any 2 different ID types, then add clear photos of each.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.lg),
          for (int i = 0; i < _docs.length; i++) ...[
            _DocOption(
              data: _docs[i],
              selected: _d.selectedDocIndexes.contains(i),
              order: _d.selectedDocIndexes.contains(i)
                  ? _d.selectedDocIndexes.indexOf(i) + 1
                  : null,
              accent: accent,
              onTap: () => _toggle(i),
            ),
            if (i != _docs.length - 1) const SizedBox(height: AppSizes.md),
          ],
        ],
      ),
    );
  }
}

/// Animated "0/2 · 1/2 · 2/2" pill — turns success-green the instant the
/// second document is picked, giving an immediate "you're done choosing" cue.
class _SelectionCounter extends StatelessWidget {
  const _SelectionCounter({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final complete = count == 2;
    return AnimatedContainer(
      duration: AppDurations.normal,
      curve: AppDurations.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: complete ? AppColors.successSoft : AppColors.surfaceMuted,
        borderRadius: AppRadii.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: AppDurations.fast,
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Icon(
              complete
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              key: ValueKey(complete),
              size: 14,
              color: complete ? AppColors.success : AppColors.textTertiary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$count / 2',
            style: AppText.caption.copyWith(
              color: complete ? AppColors.success : AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
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

class _DocOption extends StatefulWidget {
  const _DocOption({
    required this.data,
    required this.selected,
    required this.order,
    required this.accent,
    required this.onTap,
  });

  final _DocOptionData data;
  final bool selected;
  final int? order;
  final AppAccent accent;
  final VoidCallback onTap;

  @override
  State<_DocOption> createState() => _DocOptionState();
}

class _DocOptionState extends State<_DocOption> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final accent = widget.accent;
    final data = widget.data;
    final tileColor = selected
        ? (accent.isLime ? const Color(0xFFCBF24A) : AppColors.ink)
        : (accent.isLime ? const Color(0xFFECE9FB) : AppColors.surfaceMuted);
    final iconColor = selected
        ? (accent.isLime ? AppColors.textPrimary : AppColors.textOnDark)
        : AppColors.textPrimary;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down ? 0.98 : 1,
        duration: AppDurations.fast,
        curve: AppDurations.easeOut,
        child: AppCard(
          border: selected
              ? Border.all(color: AppColors.borderStrong, width: 1.6)
              : null,
          child: Row(
            children: [
              AnimatedContainer(
                duration: AppDurations.normal,
                curve: AppDurations.easeOut,
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
              _SelectBadge(selected: selected, order: widget.order),
            ],
          ),
        ),
      ),
    );
  }
}

/// Replaces a plain radio dot with the document's pick order (1 or 2) once
/// selected — pops in with a back-eased scale so choosing feels tactile.
class _SelectBadge extends StatelessWidget {
  const _SelectBadge({required this.selected, required this.order});
  final bool selected;
  final int? order;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppDurations.normal,
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: AppDurations.easeOut,
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: child),
      child: selected
          ? Container(
              key: ValueKey('sel-$order'),
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.ink,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$order',
                style: AppText.caption.copyWith(
                  color: AppColors.textOnDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : Container(
              key: const ValueKey('unsel'),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border, width: 1.6),
              ),
            ),
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

/// Step 2 — capture FRONT (+ BACK unless a passport) for each of the 2
/// chosen documents, one at a time behind an animated "Document X of 2"
/// sub-flow — mirrors [ChangePinScreen]'s custom-header shell since, like
/// that screen, back needs to step within the flow rather than just pop.
class CaptureDocumentsScreen extends StatefulWidget {
  const CaptureDocumentsScreen({super.key, required this.draft});
  final KycDraft draft;

  @override
  State<CaptureDocumentsScreen> createState() => _CaptureDocumentsScreenState();
}

class _CaptureDocumentsScreenState extends State<CaptureDocumentsScreen> {
  final _picker = ImagePicker();
  int _docStep = 0; // 0 or 1 — which of the 2 chosen documents

  KycDraft get _d => widget.draft;
  KycDocSlot get _current => _d.docs[_docStep];
  bool get _canContinue => _current.ready;

  Future<void> _pick({required bool front}) async {
    final f = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (f != null && mounted) {
      setState(() => front ? _current.front = f : _current.back = f);
    }
  }

  void _back() {
    if (_docStep == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _docStep -= 1);
    }
  }

  void _continue() {
    if (!_canContinue) return;
    if (_docStep == 0) {
      setState(() => _docStep = 1);
    } else {
      AppNav.push(context, TakeSelfieScreen(draft: _d));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.md,
                AppSizes.sm,
                AppSizes.screenPad,
                AppSizes.sm,
              ),
              child: SizedBox(
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text('Identity verification', style: AppText.title),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: _back,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '2 / 4',
                        style: AppText.label.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.screenPad,
                vertical: AppSizes.md,
              ),
              child: StepProgress(step: _docStep + 1, total: 2),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppDurations.normal,
                switchInCurve: AppDurations.easeOut,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0.06, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: _DocCaptureStep(
                  key: ValueKey(_docStep),
                  slot: _current,
                  indexLabel: 'Document ${_docStep + 1} of 2',
                  onPickFront: () => _pick(front: true),
                  onPickBack: () => _pick(front: false),
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                AppSizes.screenPad,
                AppSizes.md,
                AppSizes.screenPad,
                AppSizes.lg + MediaQuery.of(context).padding.bottom,
              ),
              child: AppButton(
                label: _docStep == 0 ? 'Next document' : 'Continue',
                trailingIcon: Icons.arrow_forward_rounded,
                enabled: _canContinue,
                onPressed: _continue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocCaptureStep extends StatelessWidget {
  const _DocCaptureStep({
    super.key,
    required this.slot,
    required this.indexLabel,
    required this.onPickFront,
    required this.onPickBack,
  });

  final KycDocSlot slot;
  final String indexLabel;
  final VoidCallback onPickFront;
  final VoidCallback onPickBack;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPad,
        AppSizes.sm,
        AppSizes.screenPad,
        AppSizes.xxl,
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: AppRadii.pill,
            ),
            child: Text(
              indexLabel,
              style: AppText.caption.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: AppSizes.md),
        Text(slot.docLabel, style: AppText.h1),
        const SizedBox(height: AppSizes.xs),
        Text('Add clear, well-lit photos.', style: AppText.body),
        const SizedBox(height: AppSizes.xl),
        _UploadBox(
          label: slot.needsBack ? 'Front of document' : 'Photo page',
          file: slot.front,
          onTap: onPickFront,
        ),
        if (slot.needsBack) ...[
          const SizedBox(height: AppSizes.md),
          _UploadBox(
            label: 'Back of document',
            file: slot.back,
            onTap: onPickBack,
          ),
        ],
      ],
    );
  }
}

/// Step 3 — capture a selfie.
class TakeSelfieScreen extends StatefulWidget {
  const TakeSelfieScreen({super.key, required this.draft});
  final KycDraft draft;

  @override
  State<TakeSelfieScreen> createState() => _TakeSelfieScreenState();
}

class _TakeSelfieScreenState extends State<TakeSelfieScreen> {
  /// Live in-app camera with on-device face detection — replaces the old
  /// stock-camera-app picker, which happily accepted a photo with no face in
  /// it at all. See LiveSelfieCameraScreen: the capture button there stays
  /// disabled until a single, centered, properly-sized face is actually
  /// being seen.
  Future<void> _pickSelfie() async {
    final f = await AppNav.push<XFile>(context, const LiveSelfieCameraScreen());
    if (f != null && mounted) setState(() => widget.draft.selfie = f);
  }

  void _continue() =>
      AppNav.push(context, ReviewSubmitScreen(draft: widget.draft));

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Identity verification',
      stepTrailing: Text('3 / 4', style: AppText.caption),
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
      final documents = <KycDocumentPayload>[];
      for (final slot in d.docs) {
        final frontUrl = await upload.uploadImage(slot.front!.path);
        final backUrl = slot.back != null
            ? await upload.uploadImage(slot.back!.path)
            : null;
        documents.add(
          KycDocumentPayload(
            docType: slot.docType,
            documentFrontUrl: frontUrl,
            documentBackUrl: backUrl,
          ),
        );
      }
      final selfieUrl = await upload.uploadImage(d.selfie!.path);
      await ref
          .read(authControllerProvider.notifier)
          .submitIdentity(documents: documents, selfieUrl: selfieUrl);
      if (!mounted) return;
      AppNav.push(
        context,
        SubmittedForReviewScreen(
          docLabels: d.docs.map((s) => s.docLabel).toList(),
        ),
      );
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
      stepTrailing: Text('4 / 4', style: AppText.caption),
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
          for (final slot in d.docs) ...[
            _ReviewRow(
              title: '${slot.docLabel} — front',
              file: slot.front,
              tile: accent.isLime
                  ? const Color(0xFFD0EEDB)
                  : AppColors.surfaceMuted,
            ),
            if (slot.back != null) ...[
              const SizedBox(height: AppSizes.md),
              _ReviewRow(
                title: '${slot.docLabel} — back',
                file: slot.back,
                tile: accent.isLime
                    ? const Color(0xFFD0EEDB)
                    : AppColors.surfaceMuted,
              ),
            ],
            const SizedBox(height: AppSizes.md),
          ],
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
  const SubmittedForReviewScreen({super.key, required this.docLabels});
  final List<String> docLabels;

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
                        '${docLabels.join(' + ')} + selfie received',
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
