import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/dto/support_dto.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/feedback/app_loaders.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/state_views.dart';

/// More → Help & support. Contact channels, an FAQ accordion, and a "contact
/// us" form that opens a support ticket. Fully theme-aware (Mono / Lime).
class HelpSupportScreen extends ConsumerStatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  ConsumerState<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends ConsumerState<HelpSupportScreen> {
  static const _categories = <String, String>{
    'transactions': 'Transactions & escrow',
    'payments': 'Payments & payouts',
    'disputes': 'Disputes',
    'verification': 'Verification',
    'account': 'Account & security',
    'other': 'Something else',
  };

  late Future<SupportOverview> _future;

  final _subject = TextEditingController();
  final _message = TextEditingController();
  String _category = 'transactions';
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _future = ref.read(supportRepositoryProvider).overview();
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  void _reload() =>
      setState(() => _future = ref.read(supportRepositoryProvider).overview());

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    AppSnackbar.success(context, '$label copied');
  }

  Future<void> _submit() async {
    final subject = _subject.text.trim();
    final message = _message.text.trim();
    if (subject.length < 3) {
      AppSnackbar.error(context, 'Add a short subject.');
      return;
    }
    if (message.length < 10) {
      AppSnackbar.error(
          context, 'Please describe your issue (at least 10 characters).');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      final ticket = await ref.read(supportRepositoryProvider).createTicket(
            category: _category,
            subject: subject,
            message: message,
          );
      if (!mounted) return;
      _subject.clear();
      _message.clear();
      AppSnackbar.success(
          context, 'Request sent — ref ${ticket.code}. We’ll reply by email.');
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
            return SizedBox(
              height: 360,
              child: ErrorRetryView(
                message: snap.hasError
                    ? friendlyError(snap.error!)
                    : 'Couldn’t load help content.',
                onRetry: _reload,
              ),
            );
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
        Text('How can we help?', style: AppText.h1),
        const SizedBox(height: AppSizes.sm),
        Text(
          'Find a quick answer below, or message our team — we usually reply '
          'within a few hours.',
          style: AppText.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSizes.xxl),

        // ── Contact channels ────────────────────────────────────────────────
        _SectionHeader(icon: Icons.support_agent_rounded, title: 'Get in touch'),
        const SizedBox(height: AppSizes.md),
        _ContactCard(contact: data.contact, onCopy: _copy),
        const SizedBox(height: AppSizes.xxl),

        // ── FAQ accordion ───────────────────────────────────────────────────
        _SectionHeader(icon: Icons.help_outline_rounded, title: 'Popular questions'),
        const SizedBox(height: AppSizes.md),
        _FaqList(faqs: data.faqs),
        const SizedBox(height: AppSizes.xxl),

        // ── Contact form ────────────────────────────────────────────────────
        _SectionHeader(icon: Icons.edit_outlined, title: 'Send us a message'),
        const SizedBox(height: AppSizes.sm),
        Text('Can’t find it above? Tell us and we’ll reply by email.',
            style: AppText.caption),
        const SizedBox(height: AppSizes.lg),
        Text('Category', style: AppText.label),
        const SizedBox(height: AppSizes.sm),
        AppDropdown<String>(
          value: _category,
          icon: Icons.category_outlined,
          items: [
            for (final e in _categories.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: AppSizes.lg),
        AppTextField(
          label: 'Subject',
          hint: 'Brief summary',
          controller: _subject,
          icon: Icons.subject_rounded,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSizes.lg),
        Text('Message', style: AppText.label),
        const SizedBox(height: AppSizes.sm),
        _MultilineField(
          controller: _message,
          hint: 'Tell us what’s going on…',
        ),
        const SizedBox(height: AppSizes.xl),
        AppButton(
          label: 'Send message',
          icon: Icons.send_rounded,
          loading: _sending,
          accentInLime: true,
          onPressed: _submit,
        ),
        const SizedBox(height: AppSizes.xl),
      ],
    );
  }
}

/// Clean section header — small accent icon + title.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppAccent.of(context).onAccentSoft),
        const SizedBox(width: AppSizes.sm),
        Text(title, style: AppText.h3),
      ],
    );
  }
}

/// Card listing the support contact channels (+ hours footer). Rows copy value.
class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contact, required this.onCopy});

  final SupportContact contact;
  final void Function(String label, String value) onCopy;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.sm, vertical: AppSizes.xs),
      child: Column(
        children: [
          _ContactRow(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'WhatsApp',
            value: contact.whatsapp,
            onTap: () => onCopy('WhatsApp number', contact.whatsapp),
          ),
          const _RowDivider(),
          _ContactRow(
            icon: Icons.mail_outline_rounded,
            label: 'Email',
            value: contact.email,
            onTap: () => onCopy('Email', contact.email),
          ),
          const _RowDivider(),
          _ContactRow(
            icon: Icons.call_outlined,
            label: 'Phone',
            value: contact.phone,
            onTap: () => onCopy('Phone number', contact.phone),
          ),
          const _RowDivider(),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.sm, vertical: AppSizes.md),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 16, color: AppColors.textTertiary),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(contact.hours,
                      style: AppText.caption
                          .copyWith(color: AppColors.textTertiary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.md,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.sm, vertical: AppSizes.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.accentSoft,
                  borderRadius: AppRadii.sm,
                ),
                child: Icon(icon, size: 20, color: accent.onAccentSoft),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(value, style: AppText.caption),
                  ],
                ),
              ),
              const Icon(Icons.copy_rounded,
                  size: 17, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.sm),
      child: Divider(height: 1),
    );
  }
}

/// All FAQs in one neat card, each a tap-to-expand row separated by dividers.
class _FaqList extends StatelessWidget {
  const _FaqList({required this.faqs});
  final List<SupportFaq> faqs;

  @override
  Widget build(BuildContext context) {
    return AppCard(
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.faq.question, style: AppText.bodyStrong),
                ),
                const SizedBox(width: AppSizes.sm),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: AppDurations.fast,
                  curve: AppDurations.easeOut,
                  child: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textSecondary),
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
                    padding: const EdgeInsets.only(bottom: AppSizes.md),
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

/// Multiline text box styled to match [AppTextField] (same fill/border/radius).
class _MultilineField extends StatefulWidget {
  const _MultilineField({required this.controller, this.hint});
  final TextEditingController controller;
  final String? hint;

  @override
  State<_MultilineField> createState() => _MultilineFieldState();
}

class _MultilineFieldState extends State<_MultilineField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return AnimatedContainer(
      duration: AppDurations.fast,
      curve: AppDurations.easeOut,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.lg, vertical: AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.md,
        border: Border.all(
          color: focused ? AppColors.borderStrong : AppColors.border,
          width: focused ? 1.6 : 1.2,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        minLines: 4,
        maxLines: 7,
        maxLength: 2000,
        cursorColor: AppColors.ink,
        style: AppText.bodyStrong,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          counterText: '',
          hintText: widget.hint,
          hintStyle: AppText.body.copyWith(
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
