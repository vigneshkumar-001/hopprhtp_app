import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../dispute/dispute_center_screen.dart';
import 'settlement_ledger_screen.dart';

/// Cooling Period — live countdown until the seller payout auto-releases.
class CoolingPeriodScreen extends StatefulWidget {
  const CoolingPeriodScreen({super.key});

  @override
  State<CoolingPeriodScreen> createState() => _CoolingPeriodScreenState();
}

class _CoolingPeriodScreenState extends State<CoolingPeriodScreen> {
  Duration _left = const Duration(hours: 23, minutes: 58, seconds: 11);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_left.inSeconds > 0) _left -= const Duration(seconds: 1);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final h = _two(_left.inHours);
    final m = _two(_left.inMinutes.remainder(60));
    final s = _two(_left.inSeconds.remainder(60));
    final accent = AppAccent.of(context);

    return AppScaffold(
      title: 'Cooling Period',
      bottomAction: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'View Details',
            trailingIcon: Icons.arrow_forward_rounded,
            onPressed: () =>
                AppNav.push(context, const SettlementLedgerScreen()),
          ),
          const SizedBox(height: AppSizes.md),
          GestureDetector(
            onTap: () => AppNav.push(context, const DisputeCenterScreen()),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.flag_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text('Raise a dispute before it ends',
                      style: AppText.bodyStrong),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          AppCard(
            color: accent.isLime
                ? const Color(0xFFD3E8F9)
                : AppColors.surfaceMuted,
            padding: const EdgeInsets.all(AppSizes.xl),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                          color: AppColors.success, shape: BoxShape.circle),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .fade(begin: 0.35, end: 1, duration: 800.ms)
                        .scaleXY(begin: 0.7, end: 1.25, duration: 800.ms),
                    const SizedBox(width: 6),
                    Text('Active Counter', style: AppText.caption),
                  ],
                ),
                const SizedBox(height: AppSizes.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TimeBlock(value: h, label: 'Hours'),
                    _Colon(),
                    _TimeBlock(value: m, label: 'Minutes'),
                    _Colon(),
                    _TimeBlock(value: s, label: 'Seconds'),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSizes.lg),
                  child: Divider(height: 1),
                ),
                Text('Expected Release Time', style: AppText.caption),
                const SizedBox(height: 4),
                Text('Tomorrow, 1:43 PM', style: AppText.h3),
                const SizedBox(height: 4),
                Text('Funds release automatically at this time if no dispute is raised.',
                    textAlign: TextAlign.center, style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Why Cooling Period?', style: AppText.h3),
                const SizedBox(height: AppSizes.sm),
                Text(
                  'Funds are protected during this window. Either party can raise a dispute if there\'s an issue. Seller payout releases automatically when it ends.',
                  style: AppText.body,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          Text('STANDARD INTERVALS',
              style: AppText.caption.copyWith(
                  letterSpacing: 1.1, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(
                child: _IntervalCard(
                  time: '1h',
                  label: 'Perishable',
                  color: accent.isLime ? const Color(0xFFD0EEDA) : null,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: _IntervalCard(
                  time: '6h',
                  label: 'Fashion',
                  color: accent.isLime ? const Color(0xFFF6E9AB) : null,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: _IntervalCard(
                  time: '24h',
                  label: 'Electronics',
                  color: accent.isLime ? const Color(0xFFE0DAF8) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppText.display.copyWith(fontSize: 40, height: 1)),
        const SizedBox(height: 4),
        Text(label, style: AppText.caption),
      ],
    );
  }
}

class _Colon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
      child: Text(':', style: AppText.display.copyWith(fontSize: 36, height: 1)),
    );
  }
}

class _IntervalCard extends StatelessWidget {
  const _IntervalCard({required this.time, required this.label, this.color});
  final String time;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: color ?? AppColors.surfaceMuted,
      padding: const EdgeInsets.symmetric(
          vertical: AppSizes.lg, horizontal: AppSizes.sm),
      child: Column(
        children: [
          Text(time, style: AppText.h2),
          const SizedBox(height: 2),
          Text(label, style: AppText.caption),
        ],
      ),
    );
  }
}
