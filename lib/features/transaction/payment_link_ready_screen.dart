import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/env/app_config.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/feedback/app_snackbar.dart';
import 'checkout_webview_screen.dart';
import 'link_transaction_screen.dart';

/// Payment Link Ready — shown after the seller taps "Generate Payment Link".
/// Surfaces the shareable link + a QR, lets the seller share it (WhatsApp / copy
/// / more), explains what happens next, then previews the buyer's payment page.
/// Accent-driven chrome follows the selected theme (lime / Mono); success +
/// brand colours (green check, WhatsApp green, amber status) stay constant.
class PaymentLinkReadyScreen extends StatefulWidget {
  const PaymentLinkReadyScreen({super.key, required this.draft, this.code});
  final PaymentDraft draft;

  /// The created transaction's public code (e.g. HTP-7Q2K). Falls back to the
  /// draft's seller code for the demo preview path.
  final String? code;

  @override
  State<PaymentLinkReadyScreen> createState() => _PaymentLinkReadyScreenState();
}

class _PaymentLinkReadyScreenState extends State<PaymentLinkReadyScreen> {
  static const int _validDays = 7;

  // Brief "Copied" confirmations on the link + the transaction-ID rows.
  bool _linkCopied = false;
  bool _codeCopied = false;

  // Computed once so the expiry doesn't drift on every rebuild.
  late final DateTime _expiresAt =
      DateTime.now().add(const Duration(days: _validDays));

  String get _code => widget.code ?? widget.draft.sellerCode;
  String get _link => '${AppConfig.webBaseUrl}/pay/$_code';

  /// The link without its scheme — cleaner to read on the card.
  String get _linkDisplay => _link.replaceFirst(RegExp(r'^https?://'), '');

  String get _shareMessage =>
      'Pay securely for your order via Hoppr escrow.\n'
      'Amount: ${Money.format(widget.draft.grandTotal)}\n'
      'Pay here: $_link';

  void _copyLink() => _copy(_link, isCode: false, label: 'Payment link copied');
  void _copyCode() =>
      _copy(_code, isCode: true, label: 'Transaction ID copied');

  void _copy(String value, {required bool isCode, required String label}) {
    Clipboard.setData(ClipboardData(text: value));
    setState(() {
      if (isCode) {
        _codeCopied = true;
      } else {
        _linkCopied = true;
      }
    });
    AppSnackbar.success(context, label);
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        if (isCode) {
          _codeCopied = false;
        } else {
          _linkCopied = false;
        }
      });
    });
  }

  /// Launch an external URI (WhatsApp / SMS / email), surfacing a friendly
  /// message if no app can handle it.
  Future<void> _launch(Uri uri, String errorLabel) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) AppSnackbar.error(context, errorLabel);
    } catch (_) {
      if (mounted) AppSnackbar.error(context, errorLabel);
    }
  }

  void _shareWhatsApp() {
    final uri =
        Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_shareMessage)}');
    _launch(uri, 'Could not open WhatsApp.');
  }

  void _shareSms() {
    final uri = Uri.parse('sms:?body=${Uri.encodeComponent(_shareMessage)}');
    _launch(uri, 'Could not open Messages.');
  }

  void _shareEmail() {
    final uri = Uri(
      scheme: 'mailto',
      query: _encodeQuery({
        'subject': 'Your Hoppr payment link',
        'body': _shareMessage,
      }),
    );
    _launch(uri, 'Could not open email.');
  }

  // Uri's queryParameters encodes spaces as "+", which some mail clients show
  // literally — build the query with %20 instead.
  String _encodeQuery(Map<String, String> params) => params.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');

  /// A themed "More options" sheet (Copy / SMS / Email) — keeps sharing on the
  /// app's own look instead of the OS sheet.
  void _moreOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.xl),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSizes.lg, AppSizes.xl, AppSizes.lg, AppSizes.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
                child: Text('Share payment link', style: AppText.h2),
              ),
              const SizedBox(height: AppSizes.lg),
              _OptionRow(
                icon: _linkCopied ? Icons.check_rounded : Icons.link_rounded,
                title: 'Copy link',
                subtitle: 'Copy to share anywhere',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _copyLink();
                },
              ),
              _OptionRow(
                icon: Icons.sms_outlined,
                title: 'Send via SMS',
                subtitle: 'Open your messaging app',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _shareSms();
                },
              ),
              _OptionRow(
                icon: Icons.mail_outline_rounded,
                title: 'Send via email',
                subtitle: 'Open your mail app',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _shareEmail();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the hosted web checkout in an in-app browser. When the buyer pays,
  /// the page hands control back and we surface the Link-transaction screen.
  Future<void> _openCheckout() async {
    final paid = await AppNav.push<bool>(
      context,
      CheckoutWebViewScreen(code: _code, lime: AppAccent.of(context).isLime),
    );
    if (paid == true && mounted) {
      AppNav.push(context, const LinkTransactionScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);

    return AppScaffold(
      title: 'Payment Link Ready',
      bottomAction: AppButton(
        label: "Preview Buyer's Payment Page",
        icon: Icons.visibility_outlined,
        trailingIcon: Icons.arrow_forward_rounded,
        accentInLime: true,
        onPressed: _openCheckout,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSizes.sm),
          // Success burst — green check with a confetti pop.
          const Center(child: _SuccessBurst()),
          const SizedBox(height: AppSizes.lg),
          Text('Payment link generated!',
              textAlign: TextAlign.center, style: AppText.h1),
          const SizedBox(height: AppSizes.sm),
          Text(
            "Share it with the buyer. They'll see the full payment breakdown "
            'and pay securely into escrow.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.xl),

          // ── Transaction ID + validity ─────────────────────────────────────
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Transaction ID', style: AppText.caption),
                          const SizedBox(height: 4),
                          Text(_code, style: AppText.h3),
                        ],
                      ),
                    ),
                    _CopyIcon(copied: _codeCopied, onTap: _copyCode),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSizes.md),
                  child: Divider(height: 1),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _LabeledValue(
                        label: 'Link valid for',
                        value: '$_validDays Days',
                      ),
                    ),
                    Expanded(
                      child: _LabeledValue(
                        label: 'Expires on',
                        value: _formatExpiry(_expiresAt),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),

          // ── Payment link + status ─────────────────────────────────────────
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payment Link', style: AppText.bodyStrong),
                const SizedBox(height: AppSizes.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.md, vertical: AppSizes.md),
                  decoration: BoxDecoration(
                    color: AppColors.cardSoft,
                    borderRadius: AppRadii.md,
                    border: Border.all(color: AppColors.border, width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.link_rounded, size: 18, color: accent.ring),
                      const SizedBox(width: AppSizes.sm),
                      Expanded(
                        child: Text(
                          _linkDisplay,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: accent.ring,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSizes.sm),
                      _CopyIcon(copied: _linkCopied, onTap: _copyLink),
                    ],
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                _StatusBanner(),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.lg),

          // ── Share actions ─────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                flex: 12,
                child: _ShareAction(
                  // Real WhatsApp logo; its badge green matches the button fill
                  // so it reads as a crisp white glyph on green.
                  leading: Image.asset(
                    'assets/images/Whatsapp_Image.png',
                    width: 21,
                    height: 21,
                    filterQuality: FilterQuality.medium,
                  ),
                  label: 'WhatsApp',
                  fill: const Color(0xFF25D366),
                  foreground: Colors.white,
                  onTap: _shareWhatsApp,
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                flex: 11,
                child: _ShareAction(
                  icon: _linkCopied ? Icons.check_rounded : Icons.copy_rounded,
                  label: _linkCopied ? 'Copied' : 'Copy Link',
                  onTap: _copyLink,
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                flex: 11,
                child: _ShareAction(
                  icon: Icons.more_horiz_rounded,
                  label: 'More Options',
                  onTap: _moreOptions,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),

          // ── Scan to open (QR) ─────────────────────────────────────────────
          AppCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Or scan to open', style: AppText.bodyStrong),
                      const SizedBox(height: 4),
                      Text(
                        'Buyer can scan this QR code to open the payment page.',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Container(
                  padding: const EdgeInsets.all(AppSizes.sm),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: AppRadii.md,
                    border: Border.all(color: accent.ring, width: 1.4),
                  ),
                  child: QrImageView(
                    data: _link,
                    version: QrVersions.auto,
                    size: 96,
                    gapless: true,
                    // Kept black-on-white for reliable scanning across themes.
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: AppColors.ink,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: AppColors.ink,
                    ),
                    errorStateBuilder: (ctx, err) => SizedBox(
                      width: 96,
                      height: 96,
                      child: Center(
                        child: Text('QR unavailable',
                            textAlign: TextAlign.center, style: AppText.caption),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),

          // ── What happens next ─────────────────────────────────────────────
          const _NextStepsCard(),
        ],
      ),
    );
  }

  /// "30 Jun 2026, 09:41 AM".
  static String _formatExpiry(DateTime d) {
    final l = d.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final m = l.minute.toString().padLeft(2, '0');
    final ampm = l.hour < 12 ? 'AM' : 'PM';
    return '${Dates.medium(l)}, ${h.toString().padLeft(2, '0')}:$m $ampm';
  }
}

// ───────────────────────────────────────────────────────────────────────────
/// Green success circle with a one-shot multicolour confetti pop behind it.
class _SuccessBurst extends StatelessWidget {
  const _SuccessBurst();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          const _ConfettiBurst(),
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.40),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.check_rounded, size: 46, color: Colors.white),
          ).popIn(),
        ],
      ),
    );
  }
}

/// A radial burst of small confetti pieces that fly out, spin and fade once.
class _ConfettiBurst extends StatelessWidget {
  const _ConfettiBurst();

  static const List<Color> _palette = [
    Color(0xFFF6C945), // yellow
    Color(0xFF2FB36B), // green
    Color(0xFF3B82F6), // blue
    Color(0xFFEC4899), // pink
    Color(0xFF8B5CF6), // purple
    Color(0xFFF97316), // orange
    Color(0xFFEF4444), // red
    Color(0xFF14B8A6), // teal
  ];

  @override
  Widget build(BuildContext context) {
    const count = 18;
    return IgnorePointer(
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [for (int i = 0; i < count; i++) _piece(i, count)],
      ),
    );
  }

  Widget _piece(int i, int count) {
    final angle = (i / count) * 2 * math.pi;
    final dist = 64.0 + (i % 4) * 18;
    final dx = math.cos(angle) * dist;
    final dy = math.sin(angle) * dist * 0.74; // flatten the spread vertically
    final color = _palette[i % _palette.length];
    final isBar = i.isEven;
    final turns = (i.isEven ? 1 : -1) * (0.6 + (i % 3) * 0.25);

    return Container(
      width: isBar ? 6 : 7,
      height: isBar ? 11 : 7,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(isBar ? 1.5 : 3.5),
      ),
    )
        .animate()
        .fadeIn(duration: 120.ms)
        .move(
          begin: Offset.zero,
          end: Offset(dx, dy),
          duration: 760.ms,
          curve: Curves.easeOutCubic,
        )
        .rotate(begin: 0, end: turns, duration: 760.ms)
        .fadeOut(delay: 560.ms, duration: 480.ms);
  }
}

/// Small copy affordance that flips to a green check when [copied].
class _CopyIcon extends StatelessWidget {
  const _CopyIcon({required this.copied, required this.onTap});
  final bool copied;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          copied ? Icons.check_rounded : Icons.copy_rounded,
          size: 18,
          color: copied ? AppColors.success : AppColors.textTertiary,
        ),
      ),
    );
  }
}

/// A small "label over value" pair (Link valid for · Expires on).
class _LabeledValue extends StatelessWidget {
  const _LabeledValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.caption),
        const SizedBox(height: 3),
        Text(value, style: AppText.bodyStrong),
      ],
    );
  }
}

/// Amber "Awaiting Buyer Payment" status strip inside the link card.
class _StatusBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md, vertical: AppSizes.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFCF4E5),
        borderRadius: AppRadii.md,
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 18, color: AppColors.warning),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Link Status', style: AppText.caption),
                const SizedBox(height: 1),
                Text(
                  'Awaiting Buyer Payment',
                  style: AppText.bodyStrong.copyWith(
                    color: const Color(0xFF9A6B14),
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

/// One share button. Filled when [fill] is set, otherwise an outlined tile.
/// Pass [leading] for a custom glyph (e.g. an image), else [icon].
class _ShareAction extends StatelessWidget {
  const _ShareAction({
    this.icon,
    this.leading,
    required this.label,
    required this.onTap,
    this.fill,
    this.foreground,
  }) : assert(icon != null || leading != null);

  final IconData? icon;
  final Widget? leading;
  final String label;
  final VoidCallback onTap;
  final Color? fill;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final filled = fill != null;
    final fg = foreground ?? AppColors.textPrimary;
    return Material(
      color: filled ? fill : AppColors.surface,
      borderRadius: AppRadii.md,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppRadii.md,
            border: filled
                ? null
                : Border.all(color: AppColors.border, width: 1.4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              leading ?? Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: AppText.bodyStrong.copyWith(color: fg),
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

/// The numbered "What happens next?" path (Pays → OTP → Delivery → Confirmed →
/// Payout). Step circles follow the theme accent.
class _NextStepsCard extends StatelessWidget {
  const _NextStepsCard();

  static const List<(String, String)> _steps = [
    ('Buyer Pays', 'into escrow'),
    ('OTP', 'generated'),
    ('Delivery', 'starts'),
    ('Delivery', 'confirmed'),
    ('Seller payout', 'after cooling'),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What happens next?', style: AppText.h3),
          const SizedBox(height: AppSizes.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < _steps.length; i++) ...[
                Expanded(
                  child: _Step(
                    number: i + 1,
                    title: _steps[i].$1,
                    subtitle: _steps[i].$2,
                    accent: accent,
                  ),
                ),
                if (i < _steps.length - 1)
                  const Padding(
                    padding: EdgeInsets.only(top: 9),
                    child: Icon(Icons.arrow_forward_rounded,
                        size: 13, color: AppColors.textTertiary),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  final int number;
  final String title;
  final String subtitle;
  final AppAccent accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.accentSoft,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: AppText.bodyStrong.copyWith(color: accent.onAccentSoft),
          ),
        ),
        const SizedBox(height: AppSizes.sm),
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppText.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppText.caption.copyWith(fontSize: 9.5, height: 1.1),
        ),
      ],
    );
  }
}

/// A row in the "More options" share sheet.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
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
                    Text(title, style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppText.caption),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
