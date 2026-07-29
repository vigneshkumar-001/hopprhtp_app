import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/network/socket_service.dart';
import '../../core/providers.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/dto/support_dto.dart';
import '../../data/dto/wallet_dto.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/blur_sheet.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_loaders.dart';
import '../../widgets/feedback/app_snackbar.dart';

const _categories = <String, String>{
  'transactions': 'Transactions & escrow',
  'payments': 'Payments & payouts',
  'withdrawal': 'Withdrawals',
  'disputes': 'Disputes',
  'verification': 'Verification',
  'account': 'Account & security',
  'other': 'Something else',
};

/// "Send us a message" — a dedicated screen for composing a support ticket
/// (reached from Help & Support's Quick Help cards or its single CTA
/// button), plus the user's own recent requests underneath.
class SupportTicketFormScreen extends ConsumerStatefulWidget {
  const SupportTicketFormScreen({super.key, this.initialCategory});

  final String? initialCategory;

  @override
  ConsumerState<SupportTicketFormScreen> createState() =>
      _SupportTicketFormScreenState();
}

class _SupportTicketFormScreenState
    extends ConsumerState<SupportTicketFormScreen> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  late String _category = widget.initialCategory ?? 'transactions';
  bool _sending = false;

  String? _selectedWithdrawalId;
  String? _selectedWithdrawalLabel;

  XFile? _attachmentFile;
  String? _attachmentUrl;
  bool _uploadingAttachment = false;

  int _ticketsRefreshToken = 0;

  StreamSubscription<SupportTicketSocketEvent>? _socketSub;
  late final SocketService _socket;

  @override
  void initState() {
    super.initState();
    _socket = ref.read(socketServiceProvider);
    // Realtime — an admin marking a ticket in review/replying/closing it
    // refreshes "My support requests" immediately, same
    // socket-triggers-a-refetch contract used across the app.
    _socketSub = _socket.supportTicketEvents.listen((event) {
      if (!mounted) return;
      setState(() => _ticketsRefreshToken++);
      AppSnackbar.info(context, 'Support request updated.');
    });
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _pickWithdrawal() async {
    final withdrawals = ref.read(walletWithdrawalsProvider).valueOrNull ?? const <WithdrawalRequest>[];
    final picked = await showBlurredSheet<WithdrawalRequest?>(
      context,
      builder: (ctx) => _PickerSheet<WithdrawalRequest>(
        title: 'Related withdrawal',
        items: withdrawals,
        labelOf: (w) => Money.format(w.amountNaira),
        subtitleOf: (w) => w.statusLabel,
      ),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _selectedWithdrawalId = picked.id;
        _selectedWithdrawalLabel = '${Money.format(picked.amountNaira)} · ${picked.statusLabel}';
      });
    }
  }

  Future<void> _pickAttachment() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (picked == null) return;
    setState(() {
      _attachmentFile = picked;
      _uploadingAttachment = true;
    });
    try {
      final url = await ref.read(uploadRepositoryProvider).uploadImage(picked.path);
      if (!mounted) return;
      setState(() => _attachmentUrl = url);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _attachmentFile = null;
        _attachmentUrl = null;
      });
      AppSnackbar.error(context, 'Could not upload the screenshot. Please try again.');
    } finally {
      if (mounted) setState(() => _uploadingAttachment = false);
    }
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
        context,
        'Please describe your issue (at least 10 characters).',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      await ref
          .read(supportRepositoryProvider)
          .createTicket(
            category: _category,
            subject: subject,
            message: message,
            withdrawalId: _selectedWithdrawalId,
            attachmentUrl: _attachmentUrl,
          );
      if (!mounted) return;
      _subject.clear();
      _message.clear();
      setState(() {
        _selectedWithdrawalId = null;
        _selectedWithdrawalLabel = null;
        _attachmentFile = null;
        _attachmentUrl = null;
        _ticketsRefreshToken++;
      });
      AppSnackbar.success(context, 'Support request submitted successfully.');
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Send us a message',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          _FormSectionHeader(
            icon: Icons.edit_note_rounded,
            title: 'Ticket details',
            subtitle: 'Tell us what’s going on — we’ll reply here and by email.',
          ),
          const SizedBox(height: AppSizes.lg),
          AppCard(
            shadow: true,
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FieldLabel(icon: Icons.dashboard_customize_rounded, label: 'Category'),
                const SizedBox(height: AppSizes.sm),
                AppDropdown<String>(
                  value: _category,
                  items: [
                    for (final e in _categories.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
                const SizedBox(height: AppSizes.lg),

                _FieldLabel(icon: Icons.short_text_rounded, label: 'Subject'),
                const SizedBox(height: AppSizes.sm),
                AppTextField(
                  hint: 'Brief summary',
                  controller: _subject,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSizes.lg),

                _FieldLabel(icon: Icons.forum_rounded, label: 'Message'),
                const SizedBox(height: AppSizes.sm),
                _MultilineField(controller: _message, hint: 'Tell us what’s going on…'),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.xxl),

          _FormSectionHeader(
            icon: Icons.link_rounded,
            title: 'Additional context',
            subtitle: 'Optional — helps us look into it faster.',
          ),
          const SizedBox(height: AppSizes.lg),
          AppCard(
            shadow: true,
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FieldLabel(icon: Icons.account_balance_wallet_rounded, label: 'Related withdrawal'),
                const SizedBox(height: AppSizes.sm),
                _OptionalLinkTile(
                  value: _selectedWithdrawalLabel,
                  placeholder: 'Attach a withdrawal request',
                  onTap: _pickWithdrawal,
                  onClear: _selectedWithdrawalLabel == null
                      ? null
                      : () => setState(() {
                          _selectedWithdrawalId = null;
                          _selectedWithdrawalLabel = null;
                        }),
                ),
                const SizedBox(height: AppSizes.lg),

                _FieldLabel(icon: Icons.add_photo_alternate_rounded, label: 'Screenshot'),
                const SizedBox(height: AppSizes.sm),
                _AttachmentTile(
                  file: _attachmentFile,
                  uploading: _uploadingAttachment,
                  uploaded: _attachmentUrl != null,
                  onTap: _pickAttachment,
                  onClear: _attachmentFile == null
                      ? null
                      : () => setState(() {
                          _attachmentFile = null;
                          _attachmentUrl = null;
                        }),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSizes.xl),
          AppButton(
            label: 'Send message',
            icon: Icons.send_rounded,
            loading: _sending,
            accentInLime: true,
            onPressed: _submit,
          ),
          const SizedBox(height: AppSizes.xxl),

          _FormSectionHeader(icon: Icons.history_rounded, title: 'My support requests'),
          const SizedBox(height: AppSizes.lg),
          _MySupportRequests(refreshToken: _ticketsRefreshToken),
          const SizedBox(height: AppSizes.xl),
        ],
      ),
    );
  }
}

/// Section header for this screen — a solid accent icon chip (the app's own
/// theme colour) + title, with an optional subtitle underneath. Distinct
/// from Help & Support's own `_SectionHeader` (private to that file) but
/// visually matching it.
class _FormSectionHeader extends StatelessWidget {
  const _FormSectionHeader({required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: accent.accent, borderRadius: AppRadii.sm),
          child: Icon(icon, size: 17, color: accent.onAccent),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.h3),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: AppText.caption),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Icon-chip + label header used above every field inside a form card — a
/// soft-accent boxed icon rather than a small bare inline glyph.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: accent.accentSoft, borderRadius: AppRadii.sm),
          child: Icon(icon, size: 14, color: accent.onAccentSoft),
        ),
        const SizedBox(width: AppSizes.sm),
        Text(label, style: AppText.label),
      ],
    );
  }
}

/// A tappable "optional context" row (Related withdrawal) — shows a
/// placeholder when nothing's picked, the picked label + a clear (x) button
/// once something is.
class _OptionalLinkTile extends StatelessWidget {
  const _OptionalLinkTile({
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.onClear,
  });

  final String? value;
  final String placeholder;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: AppRadii.md,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value ?? placeholder,
                  style: value == null
                      ? AppText.body.copyWith(color: AppColors.textTertiary)
                      : AppText.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 16, color: AppColors.textTertiary),
                  ),
                )
              else
                const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.file,
    required this.uploading,
    required this.uploaded,
    required this.onTap,
    this.onClear,
  });

  final XFile? file;
  final bool uploading;
  final bool uploaded;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: AppRadii.md,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: uploading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  file == null
                      ? 'Add a screenshot'
                      : uploading
                      ? 'Uploading screenshot…'
                      : uploaded
                      ? 'Screenshot attached'
                      : 'Upload failed — tap to retry',
                  style: file == null
                      ? AppText.body.copyWith(color: AppColors.textTertiary)
                      : AppText.bodyStrong,
                ),
              ),
              if (uploading)
                const SizedBox(width: 16, height: 16, child: AppCircularLoader(size: 16, strokeWidth: 2))
              else if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 16, color: AppColors.textTertiary),
                  ),
                )
              else
                const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
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
        horizontal: AppSizes.lg,
        vertical: AppSizes.md,
      ),
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

/// Generic "pick one from a recent list" bottom sheet.
class _PickerSheet<T> extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.items,
    required this.labelOf,
    required this.subtitleOf,
  });

  final String title;
  final List<T> items;
  final String Function(T) labelOf;
  final String Function(T) subtitleOf;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizes.xl, AppSizes.md, AppSizes.xl, AppSizes.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.h2),
          const SizedBox(height: AppSizes.md),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSizes.xl),
              child: Text('Nothing to pick from yet.', style: AppText.body),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length > 15 ? 15 : items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final item = items[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(labelOf(item), style: AppText.bodyStrong),
                    subtitle: Text(subtitleOf(item), style: AppText.caption),
                    onTap: () => Navigator.of(context).pop(item),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The user's own recent support requests — real backend status only, pull
/// to refresh. Hidden entirely when there are none yet.
class _MySupportRequests extends ConsumerStatefulWidget {
  const _MySupportRequests({required this.refreshToken});
  final int refreshToken;

  @override
  ConsumerState<_MySupportRequests> createState() => _MySupportRequestsState();
}

class _MySupportRequestsState extends ConsumerState<_MySupportRequests> {
  late Future<List<SupportTicket>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(supportRepositoryProvider).listTickets();
  }

  @override
  void didUpdateWidget(covariant _MySupportRequests oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _refresh();
  }

  Future<void> _refresh() async {
    final next = ref.read(supportRepositoryProvider).listTickets();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SupportTicket>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSizes.xl),
            child: Center(child: AppCircularLoader(size: 22, strokeWidth: 2.5)),
          );
        }
        final tickets = snap.data ?? const <SupportTicket>[];
        if (tickets.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSizes.xxl, horizontal: AppSizes.lg),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: AppRadii.card,
            ),
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 28, color: AppColors.textTertiary),
                const SizedBox(height: AppSizes.sm),
                Text(
                  'Your submitted requests will show up here.',
                  style: AppText.caption,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.ink,
          child: AppCard(
            shadow: true,
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: AppSizes.xs),
            child: Column(
              children: [
                for (int i = 0; i < tickets.length; i++) ...[
                  _SupportTicketRow(ticket: tickets[i]),
                  if (i != tickets.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SupportTicketRow extends StatelessWidget {
  const _SupportTicketRow({required this.ticket});
  final SupportTicket ticket;

  static (Color, Color) _pillColors(String status) => switch (status) {
    'open' => (AppColors.warning.withValues(alpha: 0.14), AppColors.warning),
    'in_progress' => (AppColors.info.withValues(alpha: 0.14), AppColors.info),
    'resolved' => (AppColors.successSoft, AppColors.success),
    'closed' => (AppColors.surfaceMuted, AppColors.textSecondary),
    _ => (AppColors.surfaceMuted, AppColors.textSecondary),
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _pillColors(ticket.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left accent bar — a quiet colour cue for the row's status,
          // readable even before the eye reaches the pill on the right.
          Container(
            width: 3,
            margin: const EdgeInsets.only(top: 2, right: AppSizes.md),
            height: ticket.adminResponse != null ? 62 : 34,
            decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(ticket.subject, style: AppText.bodyStrong)),
                    StatusPill(label: ticket.statusLabel, background: bg, foreground: fg, dense: true),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${ticket.code} · ${ticket.createdAt != null ? Dates.relative(ticket.createdAt!) : ''}',
                  style: AppText.caption,
                ),
                if (ticket.adminResponse != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSizes.sm),
                    decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: AppRadii.sm),
                    child: Text(ticket.adminResponse!, style: AppText.caption.copyWith(color: AppColors.textPrimary)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
