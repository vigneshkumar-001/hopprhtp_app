import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import 'widgets/transaction_widgets.dart';

enum _Phase { ready, scanning, extracted }

/// "Scan with Hoppr Vision" — capture a photo of the waybill/parcel, watch it
/// scan, then review the pre-filled fields. This is a **demo**: the fields are
/// sample values (not read from the photo) and are clearly labelled as such, so
/// the user knows to edit them. Returns `true` when confirmed (caller fills).
class ScanVisionScreen extends StatefulWidget {
  const ScanVisionScreen({super.key});

  @override
  State<ScanVisionScreen> createState() => _ScanVisionScreenState();
}

class _ScanVisionScreenState extends State<ScanVisionScreen>
    with SingleTickerProviderStateMixin {
  _Phase _phase = _Phase.ready;
  XFile? _photo;

  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  // Sample values shown in the demo — kept in sync with the caller's auto-fill.
  static const _sample = <(IconData, String, String)>[
    (Icons.inventory_2_outlined, 'Product / Item', 'MacBook Pro M2'),
    (Icons.payments_outlined, 'Declared value', '₦1,230,087'),
    (Icons.call_outlined, 'Buyer contact', '0901 234 5678'),
    (Icons.local_shipping_outlined, 'Dispatcher', 'Tunde Bello'),
    (Icons.call_outlined, 'Dispatcher phone', '+234 706 740 8881'),
    (Icons.account_balance_outlined, 'Bank', 'GTBank'),
    (Icons.numbers_rounded, 'Account', '0123456789 · Tunde Bello'),
  ];

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final x = await ImagePicker()
        .pickImage(source: source, imageQuality: 80, maxWidth: 1600);
    if (x != null && mounted) setState(() => _photo = x);
  }

  Future<void> _startScan() async {
    setState(() => _phase = _Phase.scanning);
    _scan.repeat();
    await Future<void>.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    _scan.stop();
    setState(() => _phase = _Phase.extracted);
  }

  void _rescan() => setState(() {
        _phase = _Phase.ready;
        _photo = null;
      });

  @override
  Widget build(BuildContext context) {
    final scanning = _phase == _Phase.scanning;
    final extracted = _phase == _Phase.extracted;

    return AppScaffold(
      titleWidget: const Text('Scan with Hoppr Vision', style: AppText.title),
      trailing: const _DemoTag(),
      bottomAction: _buildAction(scanning, extracted),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          if (_photo == null && !extracted)
            Text(
              'Add a photo of the waybill, shipping label or parcel and Hoppr '
              'Vision will pre-fill the transaction for you to review.',
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
            Text(scanning ? 'Reading your document…' : 'Photo ready to scan',
                style: AppText.body.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSizes.lg),

          // Picker (no photo yet) OR the photo preview with scan overlay.
          if (_photo == null && !extracted)
            _picker()
          else
            _preview(scanning: scanning, extracted: extracted),

          if (extracted) ...[
            const SizedBox(height: AppSizes.lg),
            const NoteBanner(
              icon: Icons.info_outline_rounded,
              text:
                  'Demo mode: these are sample details, not read from your photo. '
                  'Edit anything to match your item before you continue — you '
                  'stay in control of the transaction.',
            ),
            const SizedBox(height: AppSizes.lg),
            for (final f in _sample) ...[
              _SampleField(icon: f.$1, label: f.$2, value: f.$3),
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
                  Icon(Icons.photo_camera_outlined,
                      size: 30, color: AppAccent.of(context).onAccentSoft),
                  const SizedBox(height: AppSizes.md),
                  Text('Take a photo', style: AppText.bodyStrong),
                  const SizedBox(height: 2),
                  Text('Tap to open the camera',
                      style: AppText.caption),
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
              if (scanning) Positioned.fill(child: _ScanOverlay(animation: _scan)),
              if (extracted)
                Positioned(
                  top: AppSizes.sm,
                  right: AppSizes.sm,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                        color: AppColors.ink, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded,
                        size: 16, color: AppColors.textOnDark),
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
                const Icon(Icons.sync_rounded,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text('Replace photo',
                    style: AppText.label
                        .copyWith(color: AppColors.textSecondary)),
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
            onPressed: () => Navigator.of(context).pop(true),
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
                  BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One sample (demo) field — label + editable-looking value box + "Sample" tag.
class _SampleField extends StatelessWidget {
  const _SampleField({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: AppText.label)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: AppRadii.pill,
              ),
              child: Text('Sample',
                  style: AppText.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: AppColors.textSecondary)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.md,
            border: Border.all(color: AppColors.border, width: 1.2),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.textTertiary),
              const SizedBox(width: AppSizes.md),
              Expanded(child: Text(value, style: AppText.bodyStrong)),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Demo" chip in the app bar so the simulated scan is never mistaken for real.
class _DemoTag extends StatelessWidget {
  const _DemoTag();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadii.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.science_outlined,
              size: 14, color: AppColors.textPrimary),
          const SizedBox(width: 4),
          Text('Demo',
              style: AppText.caption.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
