import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';

enum _HistoryState { released, cooling, disputed }

class _HistoryItem {
  const _HistoryItem(
      this.initials, this.name, this.date, this.amount, this.state);
  final String initials;
  final String name;
  final String date;
  final String amount;
  final _HistoryState state;
}

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  int _tab = 0;
  static const _tabs = ['All', 'Active', 'Completed', 'Disputed'];

  static const _items = [
    _HistoryItem('MU', 'Musa (Dispatch)', 'Completed · 12 May 2025',
        '₦1,230,087', _HistoryState.released),
    _HistoryItem('GR', 'Grace (Buyer)', 'Cooling · 11 May 2025', '₦60,000',
        _HistoryState.cooling),
    _HistoryItem('TU', 'Tunde (Seller)', 'Completed · 10 May 2025', '₦750,000',
        _HistoryState.released),
    _HistoryItem('JO', 'John (Buyer)', 'Disputed · 10 May 2025', '₦320,000',
        _HistoryState.disputed),
  ];

  List<_HistoryItem> get _filtered {
    switch (_tab) {
      case 1:
        return _items.where((i) => i.state == _HistoryState.cooling).toList();
      case 2:
        return _items.where((i) => i.state == _HistoryState.released).toList();
      case 3:
        return _items.where((i) => i.state == _HistoryState.disputed).toList();
      default:
        return _items;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Transaction History',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              for (int i = 0; i < _tabs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: AppSizes.sm),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _tab = i);
                    },
                    child: AnimatedContainer(
                      duration: AppDurations.fast,
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.md, vertical: AppSizes.sm),
                      decoration: BoxDecoration(
                        color: i == _tab
                            ? AppColors.ink
                            : AppColors.surfaceMuted,
                        borderRadius: AppRadii.pill,
                      ),
                      child: Text(_tabs[i],
                          style: AppText.label.copyWith(
                            color: i == _tab
                                ? AppColors.textOnDark
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          // Re-staggers each time the filter tab changes.
          ..._filtered
              .map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.md),
                    child: _HistoryCard(item: item),
                  ))
              .toList()
              .staggerEnter(),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item});
  final _HistoryItem item;

  @override
  Widget build(BuildContext context) {
    final (label, icon, fg, bg) = switch (item.state) {
      _HistoryState.released => (
          'Released',
          Icons.check_rounded,
          AppColors.success,
          AppColors.successSoft
        ),
      _HistoryState.cooling => (
          'Cooling period',
          Icons.schedule_rounded,
          AppColors.textSecondary,
          AppColors.surfaceMuted
        ),
      _HistoryState.disputed => (
          'Disputed',
          Icons.flag_outlined,
          AppColors.danger,
          AppColors.surfaceMuted
        ),
    };
    return AppCard(
      child: Row(
        children: [
          InitialsAvatar(initials: item.initials, size: 42),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(item.date, style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(item.amount, style: AppText.bodyStrong),
              const SizedBox(height: 4),
              StatusPill(
                  label: label,
                  icon: icon,
                  foreground: fg,
                  background: bg,
                  dense: true),
            ],
          ),
        ],
      ),
    );
  }
}
