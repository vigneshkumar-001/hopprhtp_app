import 'package:flutter/material.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import 'widgets/transaction_widgets.dart';

enum _Phase { ready, scanning, extracted }

/// "Scan with Hoppr Vision" — upload a document, watch it scan, then review the
/// extracted fields. Returns `true` when the user confirms (caller auto-fills).
class ScanVisionScreen extends StatefulWidget {
  const ScanVisionScreen({super.key});

  @override
  State<ScanVisionScreen> createState() => _ScanVisionScreenState();
}

class _ScanVisionScreenState extends State<ScanVisionScreen>
    with SingleTickerProviderStateMixin {
  _Phase _phase = _Phase.ready;
  int _docType = 0;

  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  static const _types = [
    'Waybill',
    'Shipping label',
    'Dispatch receipt',
    'Parcel photo',
    'Delivery doc',
  ];

  static const _fields = <(IconData, String, String, bool)>[
    (Icons.person_outline_rounded, 'Buyer name', 'Amara Okafor', true),
    (Icons.call_outlined, 'Buyer phone', '0901 234 5678', true),
    (Icons.location_on_outlined, 'Delivery address',
        '14 Bourdillon Rd, Ikoyi, Lagos', false),
    (Icons.qr_code_scanner_rounded, 'Tracking reference', 'GIG-LOS-77204', true),
    (Icons.inventory_2_outlined, 'Product / Item', 'MacBook Pro M2', true),
    (Icons.payments_outlined, 'Declared value', '₦1,230,087', false),
    (Icons.scale_outlined, 'Weight', '2.1 kg', true),
  ];

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() => _phase = _Phase.scanning);
    _scan.repeat();
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;
    _scan.stop();
    setState(() => _phase = _Phase.extracted);
  }

  void _rescan() => setState(() => _phase = _Phase.ready);

  @override
  Widget build(BuildContext context) {
    final extracted = _phase == _Phase.extracted;
    final scanning = _phase == _Phase.scanning;

    return AppScaffold(
      titleWidget: const Text('Scan with Hoppr\nVision',
          textAlign: TextAlign.center, style: AppText.title),
      trailing: const _VisionTag(),
      bottomAction: _buildAction(scanning, extracted),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          if (extracted)
            Row(
              children: [
                Text('7 fields extracted', style: AppText.h3),
                const Spacer(),
                const Icon(Icons.auto_awesome_rounded,
                    size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Text('94% confidence', style: AppText.caption),
              ],
            )
          else
            Text.rich(
              TextSpan(
                style: AppText.body,
                children: const [
                  TextSpan(
                      text:
                          'Upload a waybill, shipping label, dispatch receipt or parcel photo. ',
                      style: AppText.bodyStrong),
                  TextSpan(
                      text:
                          'Hoppr Vision reads it and pre-fills the transaction for you to confirm.'),
                ],
              ),
            ),
          const SizedBox(height: AppSizes.xl),
          // Document + scanning overlay.
          Stack(
            children: [
              _WaybillPreview(checked: extracted),
              if (scanning)
                Positioned.fill(child: _ScanOverlay(animation: _scan)),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          if (extracted) ...[
            const NoteBanner(
              icon: Icons.info_outline_rounded,
              text:
                  'Hoppr Vision pre-filled these from your document. Review and edit anything before you confirm — you stay in control of the final transaction.',
            ),
            const SizedBox(height: AppSizes.lg),
            for (final f in _fields) ...[
              _VisionField(
                  icon: f.$1, label: f.$2, value: f.$3, high: f.$4),
              const SizedBox(height: AppSizes.md),
            ],
          ] else ...[
            Row(
              children: [
                const Icon(Icons.description_outlined,
                    size: 16, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      scanning
                          ? 'Reading Waybill_GIG_77204.jpg…'
                          : 'Waybill_GIG_77204.jpg · ready',
                      style: AppText.caption),
                ),
                if (!scanning)
                  GestureDetector(
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Choose a new document')),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.sync_rounded,
                            size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('Replace',
                            style: AppText.label
                                .copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),
            Wrap(
              spacing: AppSizes.sm,
              runSpacing: AppSizes.sm,
              children: [
                for (int i = 0; i < _types.length; i++)
                  GestureDetector(
                    onTap: scanning ? null : () => setState(() => _docType = i),
                    child: StatusPill(
                      label: _types[i],
                      background: i == _docType
                          ? AppColors.ink
                          : AppColors.surfaceMuted,
                      foreground: i == _docType
                          ? AppColors.textOnDark
                          : AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAction(bool scanning, bool extracted) {
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
            label: 'Confirm & pre-fill transaction',
            trailingIcon: Icons.arrow_forward_rounded,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: AppSizes.sm),
          AppButton(
            label: 'Rescan document',
            icon: Icons.refresh_rounded,
            variant: AppButtonVariant.soft,
            onPressed: _rescan,
          ),
        ],
      );
    }
    return AppButton(
      label: 'Scan with Hoppr Vision',
      icon: Icons.auto_awesome_rounded,
      variant: AppButtonVariant.outline,
      accentInLime: true,
      onPressed: _startScan,
    );
  }
}

/// Sweeping scan line + glow, clipped to the document card.
class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context).accent;
    return ClipRRect(
      borderRadius: AppRadii.card,
      child: AnimatedBuilder(
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
                        color: accent.withValues(alpha: 0.6), blurRadius: 8),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One extracted field with a confidence chip + AI badge.
class _VisionField extends StatelessWidget {
  const _VisionField({
    required this.icon,
    required this.label,
    required this.value,
    required this.high,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool high;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: AppText.label)),
            Icon(Icons.circle,
                size: 8,
                color: high ? AppColors.success : const Color(0xFFD7A33C)),
            const SizedBox(width: 4),
            Text(high ? 'High' : 'Check',
                style: AppText.caption.copyWith(
                  color: high ? AppColors.success : const Color(0xFFB07E1E),
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(width: AppSizes.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: AppRadii.pill,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 11, color: AppColors.textSecondary),
                  const SizedBox(width: 3),
                  Text('AI',
                      style: AppText.caption.copyWith(
                          fontWeight: FontWeight.w700, fontSize: 11)),
                ],
              ),
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

class _VisionTag extends StatelessWidget {
  const _VisionTag();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadii.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_rounded,
              size: 14, color: AppColors.textPrimary),
          const SizedBox(width: 4),
          Text('Hoppr Vision',
              style: AppText.caption.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _WaybillPreview extends StatelessWidget {
  const _WaybillPreview({this.checked = false});
  final bool checked;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.surface,
      shadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('GIG LOGISTICS', style: AppText.bodyStrong),
              if (checked)
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                      color: AppColors.ink, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded,
                      size: 14, color: AppColors.textOnDark),
                )
              else
                Text('WAYBILL',
                    style: AppText.caption.copyWith(letterSpacing: 1)),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSizes.md),
            child: Divider(height: 1),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _kv('SHIP TO',
                    'Amara Okafor\n14 Bourdillon Rd, Ikoyi,\nLagos · 0901 234 5678'),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv('TRACKING', 'GIG-LOS-77204'),
                    const SizedBox(height: AppSizes.md),
                    _kv('WEIGHT', '2.1 kg'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          const _Barcode(),
          const SizedBox(height: AppSizes.sm),
          Text('HTP · GIGLOS77204 · MACBOOK',
              style: AppText.caption.copyWith(fontFamily: 'monospace')),
        ],
      ),
    );
  }

  static Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: AppText.caption.copyWith(letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(v, style: AppText.bodyStrong.copyWith(fontSize: 13, height: 1.35)),
        ],
      );
}

class _Barcode extends StatelessWidget {
  const _Barcode();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      width: 160,
      child: CustomPaint(painter: _BarcodePainter()),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = AppColors.ink;
    // Deterministic bar pattern (no randomness).
    const widths = [3.0, 1.0, 2.0, 1.0, 4.0, 1.0, 2.0, 3.0, 1.0, 2.0, 1.0, 3.0];
    double x = 0;
    int i = 0;
    while (x < size.width) {
      final w = widths[i % widths.length];
      if (i.isEven) {
        canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), p);
      }
      x += w + 1.5;
      i++;
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
