import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';

class _Notice {
  const _Notice(this.icon, this.title, this.subtitle, this.time, this.unread);
  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  final bool unread;
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static const _today = [
    _Notice(Icons.account_balance_outlined, 'Seller payout released',
        '₦1,230,087.00 sent to GTBank ···· 6789', '2:14 PM', true),
    _Notice(Icons.shield_outlined, 'Delivery confirmed',
        'HTP-7Q2K · cooling period started', '1:58 PM', true),
    _Notice(Icons.chat_bubble_outline_rounded, 'OTP sent to dispatcher',
        'Tunde Bello · valid for 7 days', '1:30 PM', false),
  ];

  static const _earlier = [
    _Notice(Icons.local_shipping_outlined, 'Out for delivery',
        'Dispatcher is on the way to you', 'Yesterday', false),
    _Notice(Icons.flag_outlined, 'Dispute update',
        'Case #DSP-4471 resolved in your favour', '2 days ago', false),
    _Notice(Icons.lock_outline_rounded, 'Payment secured',
        '₦1,246,812.66 locked in escrow', '2 days ago', false),
  ];

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Notifications',
      trailing: GestureDetector(
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All marked as read')),
        ),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: AppRadii.pill,
          ),
          child: Text('Mark read',
              style: AppText.caption.copyWith(fontWeight: FontWeight.w700)),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          _Group(label: 'Today', items: _today),
          const SizedBox(height: AppSizes.lg),
          _Group(label: 'Earlier', items: _earlier),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.label, required this.items});
  final String label;
  final List<_Notice> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: AppText.caption.copyWith(
                letterSpacing: 1.1, fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSizes.md),
        AppCard(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.lg, vertical: AppSizes.xs),
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _NoticeRow(notice: items[i]),
                if (i != items.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.notice});
  final _Notice notice;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: AppRadii.sm,
            ),
            child: Icon(notice.icon, size: 18),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notice.title, style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(notice.subtitle, style: AppText.caption),
                const SizedBox(height: 4),
                Text(notice.time, style: AppText.caption),
              ],
            ),
          ),
          if (notice.unread)
            Container(
              margin: const EdgeInsets.only(top: 4),
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: AppColors.ink, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}
