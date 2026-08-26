import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/dto/support_dto.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/feedback/app_loaders.dart';
import '../../widgets/feedback/app_snackbar.dart';
import 'support_ticket_form_screen.dart';

/// A Quick Help category — tapping one jumps straight to
/// [SupportTicketFormScreen] with that category pre-selected, so "I have a
/// withdrawal issue" takes one tap instead of hunting through a dropdown.
class _QuickHelp {
  const _QuickHelp(this.icon, this.label, this.category);
  final IconData icon;
  final String label;
  final String category;
}

const _quickHelp = <_QuickHelp>[
  _QuickHelp(Icons.payments_rounded, 'Payment Issue', 'payments'),
  _QuickHelp(Icons.account_balance_rounded, 'Withdrawal Issue', 'withdrawal'),
  _QuickHelp(Icons.local_shipping_rounded, 'Delivery / OTP Issue', 'transactions'),
  _QuickHelp(Icons.gavel_rounded, 'Dispute Help', 'disputes'),
  _QuickHelp(Icons.verified_user_rounded, 'KYC / Verification', 'verification'),
  _QuickHelp(Icons.person_rounded, 'Account / Login', 'account'),
];

/// More → Help & support. A premium dark hero, Quick Help shortcuts, an FAQ
/// accordion, and a single CTA into [SupportTicketFormScreen] for anything
/// not covered above. Fully theme-aware (Mono / Lime).
class HelpSupportScreen extends ConsumerStatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  ConsumerState<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends ConsumerState<HelpSupportScreen> {
  late Future<SupportOverview> _future;

  // Tracks the error last surfaced via snackbar so a rebuild while still in
  // the same error state doesn't re-show it — only a fresh failed fetch does.
  Object? _lastNotifiedError;

  @override
  void initState() {
    super.initState();
    _future = ref.read(supportRepositoryProvider).overview();
  }

  void _reload() => setState(() {
    _lastNotifiedError = null;
    _future = ref.read(supportRepositoryProvider).overview();
  });

  void _openForm({String? category}) {
    AppNav.push(context, SupportTicketFormScreen(initialCategory: category));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Help & support',
      body: FutureBuilder<SupportOverview>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 360,
              child: Center(child: AppCircularLoader()),
            );
          }
          if (snap.hasError || !snap.hasData) {
            final error = snap.error;
            if (error != null && !identical(error, _lastNotifiedError)) {
              _lastNotifiedError = error;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  AppSnackbar.error(
                    context,
                    friendlyError(error),
                    onRetry: _reload,
                    autoRetryOnReconnect:
                        error is ApiException && error.isConnectionIssue,
                  );
                }
              });
            }
            return const SizedBox(height: 360);
          }
          return _content(snap.data!);
        },
      ),
    );
  }

  Widget _content(SupportOverview data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSizes.sm),
        const _SupportHero(),
        const SizedBox(height: AppSizes.xxl),

        // ── Quick Help ──────────────────────────────────────────────────────
        _SectionHeader(icon: Icons.bolt_rounded, title: 'Quick Help'),
        const SizedBox(height: AppSizes.md),
        _QuickHelpGrid(onTap: (h) => _openForm(category: h.category)),
        const SizedBox(height: AppSizes.xxl),

        // ── FAQ accordion ───────────────────────────────────────────────────
        _SectionHeader(icon: Icons.help_outline_rounded, title: 'Popular questions'),
        const SizedBox(height: AppSizes.md),
        _FaqList(faqs: data.faqs),
        const SizedBox(height: AppSizes.xxl),

        // ── Still need help? ────────────────────────────────────────────────
        _StillNeedHelpCard(onPressed: () => _openForm()),
        const SizedBox(height: AppSizes.xl),
      ],
    );
  }
}

/// Dark gradient hero — same brand treatment as the Wallet balance card and
/// Profile header ([DarkCard]), just with a support-specific icon + copy
/// instead of a money figure.
class _SupportHero extends StatelessWidget {
  const _SupportHero();

  @override
  Widget build(BuildContext context) {
    return DarkCard(
      radius: AppRadii.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(height: AppSizes.lg),
          const Text(
            'How can we help?',
            style: TextStyle(
              fontFamily: AppText.fontFamily,
              fontSize: 26,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Get help with payments, delivery, withdrawals, disputes, or account verification.',
            style: TextStyle(
              fontFamily: AppText.fontFamily,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

/// 2-column grid of quick-help category shortcuts — a solid accent icon chip
/// (the app's own theme colour, not an invented palette) and a tactile
/// press-scale (matching [AppButton]'s press feel).
class _QuickHelpGrid extends StatelessWidget {
  const _QuickHelpGrid({required this.onTap});
  final void Function(_QuickHelp) onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: AppSizes.md,
      crossAxisSpacing: AppSizes.md,
      childAspectRatio: 2.15,
      children: [for (final h in _quickHelp) _QuickHelpCard(help: h, onTap: () => onTap(h))],
    );
  }
}

class _QuickHelpCard extends StatefulWidget {
  const _QuickHelpCard({required this.help, required this.onTap});
  final _QuickHelp help;
  final VoidCallback onTap;

  @override
  State<_QuickHelpCard> createState() => _QuickHelpCardState();
}

class _QuickHelpCardState extends State<_QuickHelpCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: AppDurations.fast,
        curve: AppDurations.easeOut,
        child: Container(
          padding: const EdgeInsets.all(AppSizes.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.card,
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: accent.accent, borderRadius: AppRadii.sm),
                child: Icon(widget.help.icon, size: 18, color: accent.onAccent),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Text(
                  widget.help.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section header with a soft accent icon chip instead of a bare icon.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: accent.accentSoft, borderRadius: AppRadii.sm),
          child: Icon(icon, size: 15, color: accent.onAccentSoft),
        ),
        const SizedBox(width: AppSizes.sm),
        Text(title, style: AppText.h3),
      ],
    );
  }
}

/// All FAQs in one elevated card, each a tap-to-expand row with its own
/// small icon chip, separated by dividers.
class _FaqList extends StatelessWidget {
  const _FaqList({required this.faqs});
  final List<SupportFaq> faqs;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      shadow: true,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
      child: Column(
        children: [
          for (int i = 0; i < faqs.length; i++) ...[
            _FaqRow(faq: faqs[i]),
            if (i != faqs.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _FaqRow extends StatefulWidget {
  const _FaqRow({required this.faq});
  final SupportFaq faq;

  @override
  State<_FaqRow> createState() => _FaqRowState();
}

class _FaqRowState extends State<_FaqRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(top: 1),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _open ? accent.accent : accent.accentSoft,
                    borderRadius: AppRadii.sm,
                  ),
                  child: Text(
                    '?',
                    style: TextStyle(
                      fontFamily: AppText.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _open ? accent.onAccent : accent.onAccentSoft,
                    ),
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Text(widget.faq.question, style: AppText.bodyStrong),
                ),
                const SizedBox(width: AppSizes.sm),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: AppDurations.fast,
                  curve: AppDurations.easeOut,
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: AppDurations.normal,
            curve: AppDurations.easeOut,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.only(left: 40, bottom: AppSizes.md),
                    child: Text(
                      widget.faq.answer,
                      style: AppText.body.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// The closing CTA block — icon + heading + subtext + button inside one
/// elevated card, instead of a bare floating button.
class _StillNeedHelpCard extends StatelessWidget {
  const _StillNeedHelpCard({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return AppCard(
      shadow: true,
      padding: const EdgeInsets.all(AppSizes.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: accent.accentSoft, borderRadius: AppRadii.md),
            child: Icon(Icons.chat_bubble_outline_rounded, size: 21, color: accent.onAccentSoft),
          ),
          const SizedBox(height: AppSizes.md),
          Text('Still need help?', style: AppText.h3),
          const SizedBox(height: 4),
          Text(
            'Send us a message and we’ll get back to you here and by email.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.lg),
          AppButton(
            label: 'Send us a message',
            icon: Icons.send_rounded,
            accentInLime: true,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}
