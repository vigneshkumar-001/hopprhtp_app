import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/dto/scan_dto.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_snackbar.dart';
import 'widgets/transaction_widgets.dart';

enum _Phase { ready, scanning, extracted }

/// Icons shown next to each of [ScanFields.displayFields], in the same order.
const _fieldIcons = <IconData>[
  Icons.person_outline_rounded, // Buyer name
  Icons.call_outlined, // Buyer phone
  Icons.local_shipping_outlined, // Dispatcher phone
  Icons.inventory_2_outlined, // Item name
  Icons.notes_outlined, // Item description
  Icons.payments_outlined, // Amount
  Icons.schedule_rounded, // Estimated delivery
  Icons.location_on_outlined, // Dispatcher address
  Icons.location_on_outlined, // Delivery address
  Icons.sticky_note_2_outlined, // Package notes
];

/// "Scan with Hoppr Vision" — capture a photo of the waybill/parcel, upload
/// it for extraction, then review the detected fields before applying
/// anything. Real upload + real backend response; never fabricates a value —
/// a field the backend didn't detect is shown as "Not detected", not a
/// guessed sample. Returns the [ScanResult] when the user confirms, or null
/// if they back out — the caller decides how to apply it.
class ScanVisionScreen extends ConsumerStatefulWidget {
  const ScanVisionScreen({super.key});

  @override
  ConsumerState<ScanVisionScreen> createState() => _ScanVisionScreenState();
}

class _ScanVisionScreenState extends ConsumerState<ScanVisionScreen>
    with SingleTickerProviderStateMixin {
  _Phase _phase = _Phase.ready;
  XFile? _photo;
  ScanResult? _result;

  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final x = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (x != null && mounted) setState(() => _photo = x);
  }

  Future<void> _startScan() async {
    final photo = _photo;
    if (photo == null) return;
    setState(() => _phase = _Phase.scanning);
    _scan.repeat();
    try {
      final result = await ref
          .read(transactionRepositoryProvider)
          .scanDocument(photo.path);
      if (!mounted) return;
      _scan.stop();
      setState(() {
        _result = result;
        _phase = _Phase.extracted;
      });
    } catch (e) {
      _scan.stop();
      if (!mounted) return;
      // Back to "photo ready" (not extracted) so the same photo can be
      // retried without re-picking it.
      setState(() => _phase = _Phase.ready);
      AppSnackbar.error(context, friendlyError(e), onRetry: _startScan);
    }
  }

  void _rescan() => setState(() {
    _phase = _Phase.ready;
    _photo = null;
    _result = null;
  });

  @override
  Widget build(BuildContext context) {
    final scanning = _phase == _Phase.scanning;
    final extracted = _phase == _Phase.extracted;
    final result = _result;

    return AppScaffold(
      titleWidget: const Text('Scan with Hoppr Vision', style: AppText.title),
      bottomAction: _buildAction(scanning, extracted),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          if (_photo == null && !extracted)
            Text(
              'Add a photo of the waybill, shipping label or parcel and Hoppr '
              'Vision will suggest transaction details for you to review.',
              style: AppText.body.copyWith(color: AppColors.textSecondary),
            )
          else if (extracted)
            Row(
              children: [
                Text('Suggested details', style: AppText.h3),
                const Spacer(),
                Text('Tap any field to edit', style: AppText.caption),
              ],
            )
          else
            Text(
              scanning ? 'Reading your document…' : 'Photo ready to scan',
              style: AppText.body.copyWith(color: AppColors.textSecondary),
            ),
          const SizedBox(height: AppSizes.lg),

          // Picker (no photo yet) OR the photo preview with scan overlay.
          if (_photo == null && !extracted)
            _picker()
          else
            _preview(scanning: scanning, extracted: extracted),

          if (extracted && result != null) ...[
            const SizedBox(height: AppSizes.lg),
            if (result.warnings.isNotEmpty) ...[
              NoteBanner(
                icon: Icons.info_outline_rounded,
                text: result.warnings.join(' '),
              ),
              const SizedBox(height: AppSizes.lg),
            ],
            for (final (i, f) in result.fields.displayFields.indexed) ...[
              _DetectedField(icon: _fieldIcons[i], label: f.$1, value: f.$2),
              const SizedBox(height: AppSizes.md),
            ],
          ],
          const SizedBox(height: AppSizes.sm),
        ],
      ),
    );
  }

  Widget _picker() {
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _pick(ImageSource.camera),
          child: DottedBorderBox(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSizes.xxxl),
              child: Column(
                children: [
                  Icon(
                    Icons.photo_camera_outlined,
                    size: 30,
                    color: AppAccent.of(context).onAccentSoft,
                  ),
                  const SizedBox(height: AppSizes.md),
                  Text('Take a photo', style: AppText.bodyStrong),
                  const SizedBox(height: 2),
                  Text('Tap to open the camera', style: AppText.caption),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSizes.md),
        AppButton(
          label: 'Choose from gallery',
          icon: Icons.photo_library_outlined,
          variant: AppButtonVariant.soft,
          onPressed: () => _pick(ImageSource.gallery),
        ),
      ],
    );
  }

  Widget _preview({required bool scanning, required bool extracted}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: AppRadii.card,
          child: Stack(
            children: [
              Container(
                height: 340,
                width: double.infinity,
                color: AppColors.surfaceMuted,
                child: _photo == null
                    ? const SizedBox.shrink()
                    : Image.file(File(_photo!.path), fit: BoxFit.cover),
              ),
              if (scanning)
                Positioned.fill(child: _ScanOverlay(animation: _scan)),
              if (extracted)
                Positioned(
                  top: AppSizes.sm,
                  right: AppSizes.sm,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: AppColors.ink,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: AppColors.textOnDark,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!scanning && !extracted) ...[
          const SizedBox(height: AppSizes.sm),
          GestureDetector(
            onTap: () => setState(() => _photo = null),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.sync_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Replace photo',
                  style: AppText.label.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget? _buildAction(bool scanning, bool extracted) {
    if (scanning) {
      return const AppButton(
        label: 'Scanning your document…',
        loading: true,
        enabled: false,
      );
    }
    if (extracted) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'Use these details',
            trailingIcon: Icons.arrow_forward_rounded,
            accentInLime: true,
            onPressed: () => Navigator.of(context).pop(_result),
          ),
          const SizedBox(height: AppSizes.sm),
          AppButton(
            label: 'Rescan',
            icon: Icons.refresh_rounded,
            variant: AppButtonVariant.soft,
            onPressed: _rescan,
          ),
        ],
      );
    }
    if (_photo == null) return null;
    return AppButton(
      label: 'Scan with Hoppr Vision',
      icon: Icons.auto_awesome_rounded,
      accentInLime: true,
      onPressed: _startScan,
    );
  }
}

/// Sweeping scan line + glow, clipped to the photo.
class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context).accent;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Align(
          alignment: Alignment(0, -1.15 + 2.3 * animation.value),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withValues(alpha: 0),
                  accent.withValues(alpha: 0.16),
                ],
              ),
            ),
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 2.5,
              decoration: BoxDecoration(
                color: accent,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.6),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One reviewed field — label + value box + a "Detected"/"Not detected" tag.
/// A null/blank [value] is shown honestly as not found, never a guess.
class _DetectedField extends StatelessWidget {
  const _DetectedField({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final detected = (value ?? '').trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: AppText.label)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: detected
                    ? AppColors.successSoft
                    : AppColors.surfaceMuted,
                borderRadius: AppRadii.pill,
              ),
              child: Text(
                detected ? 'Detected' : 'Not detected',
                style: AppText.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: detected ? AppColors.success : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.lg,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.md,
            border: Border.all(color: AppColors.border, width: 1.2),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.textTertiary),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Text(
                  detected ? value! : 'Not found in photo — enter manually',
                  style: detected
                      ? AppText.bodyStrong
                      : AppText.body.copyWith(color: AppColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
