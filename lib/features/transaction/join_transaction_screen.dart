import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/feedback/app_snackbar.dart';
import 'buyer_review_screen.dart';

/// Enter Transaction Code — the buyer types the HTP code the seller shared to
/// join a transaction. This restores the original segmented-code UI (the
/// "HTP – ▢ ▢ ▢ ▢" box) on top of the real backend join logic.
///
/// Real transaction codes are `HTP-` + 4 characters from an alphanumeric
/// alphabet (e.g. `HTP-7Q2K`), so the 4 slots map exactly to a real code — but
/// entry is alphanumeric (the old numeric keypad couldn't type letters like
/// Q/K, and the fake 4-digit demo flow it belonged to is gone).
///
/// This is **not** delivery confirmation: the delivery code (buyer → seller,
/// after the product arrives) is a separate screen and is never mixed in here.
///
/// Flow: enter code → `GET /transactions/code/:code` → [BuyerReviewScreen],
/// which owns every outcome (seller's own link, already paid, dead
/// transaction, or the real review-and-pay flow) for whatever was found — this
/// screen only ever handles a fetch that FAILED (invalid/expired/network).
class JoinTransactionScreen extends ConsumerStatefulWidget {
  const JoinTransactionScreen({super.key});

  @override
  ConsumerState<JoinTransactionScreen> createState() =>
      _JoinTransactionScreenState();
}

class _JoinTransactionScreenState extends ConsumerState<JoinTransactionScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  bool _loading = false;

  /// Real codes are `HTP-` + exactly 4 alphanumeric characters.
  static const _len = 4;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The 4-character segment the user typed (already upper-cased + filtered by
  /// [_CodeSegmentFormatter]); the "HTP–" prefix is fixed UI chrome.
  String get _segment => _controller.text;

  /// The full code sent to the backend, matching its stored form.
  String get _fullCode => 'HTP-$_segment';

  bool get _complete => _segment.length == _len;

  void _onChanged() {
    // Rebuild so the segmented boxes fill in as the user types.
    setState(() {});
  }

  Future<void> _submit() async {
    if (_loading || !_complete) return;
    FocusScope.of(context).unfocus();

    setState(() => _loading = true);

    try {
      final tx = await ref
          .read(transactionRepositoryProvider)
          .getByCode(_fullCode);
      if (!mounted) return;
      setState(() => _loading = false);
      // BuyerReviewScreen owns every outcome for a successfully-fetched
      // transaction (seller's own link, already paid, dead, or the real
      // review-and-pay flow) — this screen only handles fetch failures.
      AppNav.push(context, BuyerReviewScreen(tx: tx));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackbar.error(context, _messageFor(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackbar.error(context, 'Something went wrong. Please try again.');
    }
  }

  /// Maps a backend/transport error to friendly inline copy.
  String _messageFor(ApiException e) {
    if (e.isConnectionIssue) {
      return "Can't reach the server. Check your connection and tap Find "
          'transaction to retry.';
    }
    final msg = e.message.toLowerCase();
    if (msg.contains('expired')) {
      return 'This transaction link has expired. Please ask the seller for a new link.';
    }
    // 404 / not-found (unknown or removed code) — the backend treats a missing
    // code as not found, which also covers an expired/rotated link.
    if (e.statusCode == 404 || msg.contains('no transaction')) {
      return 'Invalid or expired transaction code.';
    }
    return e.userMessage;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Enter Transaction Code',
      scrollable: false,
      bottomAction: AppButton(
        label: 'Find transaction',
        trailingIcon: Icons.arrow_forward_rounded,
        loading: _loading,
        enabled: _complete && !_loading,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSizes.sm),
          Text(
            'Enter the code shared by the seller to join this transaction '
            'securely.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.xl),
          _CodeBox(
            segment: _segment,
            length: _len,
            controller: _controller,
            focusNode: _focus,
            enabled: !_loading,
            onSubmit: _submit,
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            'e.g. HTP-7Q2K',
            textAlign: TextAlign.center,
            style: AppText.caption,
          ),
          const SizedBox(height: AppSizes.xl),
          // Escrow protection info — reassures the buyer their money is safe.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 16,
                color: AppColors.success,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Your payment is protected in escrow until delivery is '
                  'confirmed.',
                  textAlign: TextAlign.center,
                  style: AppText.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The restored segmented code box: a fixed "HTP" + "–" prefix followed by
/// [length] slots that fill with the typed characters (dots until typed). A
/// transparent, auto-focused field over the box captures the actual keystrokes,
/// so entry is alphanumeric (real codes contain letters) while the visual is
/// the original design.
class _CodeBox extends StatelessWidget {
  const _CodeBox({
    required this.segment,
    required this.length,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSubmit,
  });

  final String segment;
  final int length;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? focusNode.requestFocus : null,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          Container(
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.md,
              border: Border.all(color: AppColors.border, width: 1.2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('HTP', style: AppText.h2.copyWith(letterSpacing: 4)),
                const SizedBox(width: AppSizes.sm),
                Text('–', style: AppText.h2),
                const SizedBox(width: AppSizes.sm),
                for (int i = 0; i < length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: i < segment.length
                        ? Text(segment[i], style: AppText.h2)
                        : Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: AppColors.textTertiary,
                              shape: BoxShape.circle,
                            ),
                          ),
                  ),
              ],
            ),
          ),
          // Invisible input on top of the box: captures taps + keystrokes.
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                enabled: enabled,
                showCursor: false,
                enableSuggestions: false,
                autocorrect: false,
                // visiblePassword → an alphanumeric keyboard with no autocorrect.
                keyboardType: TextInputType.visiblePassword,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                inputFormatters: [_CodeSegmentFormatter(length)],
                onSubmitted: (_) => onSubmit(),
                style: const TextStyle(color: Colors.transparent),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps the code segment to [maxLen] upper-case alphanumeric characters, and
/// tolerates pasting a full `HTP-XXXX` code by stripping the `HTP-` prefix.
class _CodeSegmentFormatter extends TextInputFormatter {
  _CodeSegmentFormatter(this.maxLen);
  final int maxLen;

  static final _nonAlnum = RegExp(r'[^A-Z0-9]');
  static final _htpPrefix = RegExp(r'^HTP-?');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.toUpperCase().replaceFirst(_htpPrefix, '');
    text = text.replaceAll(_nonAlnum, '');
    if (text.length > maxLen) text = text.substring(0, maxLen);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
