import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/app_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';

/// Identity verification intro (mockup 7) + a lightweight working flow.
class IdentityVerificationScreen extends StatelessWidget {
  const IdentityVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return AppScaffold(
      title: 'Identity verification',
      bottomAction: AppButton(
        label: 'Start verification',
        trailingIcon: Icons.arrow_forward_rounded,
        onPressed: () =>
            AppNav.push(context, const ChooseDocumentScreen()),
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
                    // Rounded-square ("half") tile, not a full circle.
                    borderRadius: AppRadii.md,
                  ),
                  child: Icon(Icons.verified_outlined,
                      color: accent.isLime
                          ? const Color(0xFFCBF24A)
                          : AppColors.textOnDark,
                      size: 26),
                ),
                const SizedBox(height: AppSizes.lg),
                Text('Get the HTP Verified badge', style: AppText.h2),
                const SizedBox(height: AppSizes.sm),
                Text(
                  'Verified accounts win more buyers, unlock higher transaction limits, and rank higher in trust scores.',
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
            subtitle: 'Clear photo of the document',
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

/// Choose-a-document step — pick an ID type, (mock) upload it, then run the
/// capture/selfie verification flow.
class ChooseDocumentScreen extends StatefulWidget {
  const ChooseDocumentScreen({super.key});

  @override
  State<ChooseDocumentScreen> createState() => _ChooseDocumentScreenState();
}

class _DocOptionData {
  const _DocOptionData(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _ChooseDocumentScreenState extends State<ChooseDocumentScreen> {
  int? _selected;
  XFile? _idImage;
  final _picker = ImagePicker();

  static const _docs = [
    _DocOptionData('National ID (NIN)', Icons.person_outline_rounded),
    _DocOptionData('Driver\'s licence', Icons.directions_car_outlined),
    _DocOptionData('International passport', Icons.public_outlined),
  ];

  Future<void> _pickId() async {
    final f = await _picker.pickImage(source: ImageSource.gallery);
    if (f != null && mounted) setState(() => _idImage = f);
  }

  void _continue() {
    AppNav.push(
      context,
      TakeSelfieScreen(docLabel: _docs[_selected!].label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return AppScaffold(
      title: 'Identity verification',
      bottomAction: AppButton(
        label: 'Continue',
        trailingIcon: Icons.arrow_forward_rounded,
        enabled: _selected != null,
        onPressed: _continue,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          Text('Choose a document', style: AppText.h1),
          const SizedBox(height: AppSizes.xs),
          Text('Select the ID type you want to upload.', style: AppText.body),
          const SizedBox(height: AppSizes.lg),
          for (int i = 0; i < _docs.length; i++) ...[
            _DocOption(
              data: _docs[i],
              selected: _selected == i,
              accent: accent,
              onTap: () => setState(() => _selected = i),
            ),
            if (i != _docs.length - 1) const SizedBox(height: AppSizes.md),
          ],
          if (_selected != null) ...[
            const SizedBox(height: AppSizes.xl),
            SectionLabel('Upload ${_docs[_selected!].label}'),
            const SizedBox(height: AppSizes.md),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pickId,
              child: DottedBorderBox(
                fill: AppColors.surfaceMuted,
                active: _idImage != null,
                child: SizedBox(
                  height: 150,
                  width: double.infinity,
                  child: _idImage != null
                      ? _PickedImage(file: _idImage!)
                      : const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image_outlined,
                                  size: 30, color: AppColors.textTertiary),
                              SizedBox(height: 8),
                              Text('Tap to upload front of ID',
                                  style: AppText.caption),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A single selectable document row (icon tile + label + radio).
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
    // Selected tile is lime in the Lime theme (ink in Mono); unselected is a
    // soft lilac (muted grey in Mono).
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

/// Round radio indicator — filled black tick when selected, hollow otherwise.
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
          ? const Icon(Icons.check_rounded, size: 14, color: AppColors.textOnDark)
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

/// Submitted-for-review confirmation — shown after the user submits their
/// documents. Grants the HTP Verified badge (prototype) and routes back.
class SubmittedForReviewScreen extends StatefulWidget {
  const SubmittedForReviewScreen({super.key, required this.docLabel});
  final String docLabel;

  @override
  State<SubmittedForReviewScreen> createState() =>
      _SubmittedForReviewScreenState();
}

class _SubmittedForReviewScreenState extends State<SubmittedForReviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.read(context).markVerified();
    });
  }

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
          Text('Submitted for review',
              textAlign: TextAlign.center, style: AppText.h1),
          const SizedBox(height: AppSizes.sm),
          Text(
            'We\'re reviewing your documents. Most verifications complete within a few minutes — we\'ll notify you.',
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
                  child: const Icon(Icons.schedule_rounded,
                      size: 20, color: AppColors.textPrimary),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status: Pending', style: AppText.bodyStrong),
                      const SizedBox(height: 2),
                      Text('${widget.docLabel} + selfie received',
                          style: AppText.caption),
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

/// Take-a-selfie step — pick a selfie from the gallery, then continue to review.
class TakeSelfieScreen extends StatefulWidget {
  const TakeSelfieScreen({super.key, required this.docLabel});
  final String docLabel;

  @override
  State<TakeSelfieScreen> createState() => _TakeSelfieScreenState();
}

class _TakeSelfieScreenState extends State<TakeSelfieScreen> {
  XFile? _selfie;
  final _picker = ImagePicker();

  Future<void> _pickSelfie() async {
    final f = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
    );
    if (f != null && mounted) setState(() => _selfie = f);
  }

  void _continue() {
    AppNav.push(context, ReviewSubmitScreen(docLabel: widget.docLabel));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Identity verification',
      bottomAction: AppButton(
        label: 'Continue',
        trailingIcon: Icons.arrow_forward_rounded,
        enabled: _selfie != null,
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
            child: _SelfieCircle(file: _selfie),
          ),
          const SizedBox(height: AppSizes.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: const [
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

/// Dashed circle "Add selfie" target.
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
            color: added ? AppColors.success : AppColors.border),
        child: added
            ? Padding(
                padding: const EdgeInsets.all(6),
                child: ClipOval(child: _PickedImage(file: file!)),
              )
            : const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined,
                        size: 30, color: AppColors.textTertiary),
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
    return Image.memory(b,
        fit: BoxFit.cover, width: double.infinity, height: double.infinity);
  }
}

class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, size.width / 2,
        Paint()..color = AppColors.surfaceMuted.withValues(alpha: 0.4));

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
              color: AppColors.successSoft, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded,
              size: 16, color: AppColors.success),
        ),
        const SizedBox(height: 6),
        Text(label, style: AppText.caption),
      ],
    );
  }
}

/// Review & submit step — confirm the uploaded ID + selfie, then submit.
class ReviewSubmitScreen extends StatelessWidget {
  const ReviewSubmitScreen({super.key, required this.docLabel});
  final String docLabel;

  void _submit(BuildContext context) {
    AppNav.push(context, SubmittedForReviewScreen(docLabel: docLabel));
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return AppScaffold(
      title: 'Identity verification',
      bottomAction: AppButton(
        label: 'Submit for verification',
        icon: Icons.verified_outlined,
        accentInLime: true,
        onPressed: () => _submit(context),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          Text('Review & submit', style: AppText.h1),
          const SizedBox(height: AppSizes.xs),
          Text('Confirm everything looks right before submitting.',
              style: AppText.body),
          const SizedBox(height: AppSizes.lg),
          _ReviewRow(
            icon: Icons.crop_free_rounded,
            title: docLabel,
            status: 'Uploaded',
            tile: accent.isLime ? const Color(0xFFD0EEDB) : AppColors.surfaceMuted,
          ),
          const SizedBox(height: AppSizes.md),
          _ReviewRow(
            icon: Icons.camera_alt_outlined,
            title: 'Selfie',
            status: 'Captured',
            tile: accent.isLime ? const Color(0xFFF7EBB0) : AppColors.surfaceMuted,
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
                Icon(Icons.info_outline_rounded,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    'By submitting you confirm these documents are genuine and belong to you.',
                    style: AppText.caption
                        .copyWith(color: AppColors.textSecondary),
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
    required this.icon,
    required this.title,
    required this.status,
    required this.tile,
  });

  final IconData icon;
  final String title;
  final String status;
  final Color tile;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tile, borderRadius: AppRadii.sm),
            child: Icon(icon, size: 20, color: AppColors.textPrimary),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(status,
                    style: AppText.caption.copyWith(color: AppColors.success)),
              ],
            ),
          ),
          const Icon(Icons.check_circle_outline_rounded,
              size: 22, color: AppColors.success),
        ],
      ),
    );
  }
}
