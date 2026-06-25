import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
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
import '../../widgets/app_text_field.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_loaders.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/segmented_control.dart';
import 'payment_setup_screen.dart';
import 'scan_vision_screen.dart';

/// Create Transaction (mockup 8). Supports multiple consignments, a "Hoppr
/// Vision" auto-fill shortcut, image-upload placeholders and courier payout.
class CreateTransactionScreen extends StatefulWidget {
  const CreateTransactionScreen({super.key});

  @override
  State<CreateTransactionScreen> createState() =>
      _CreateTransactionScreenState();
}

class _CreateTransactionScreenState extends State<CreateTransactionScreen> {
  final List<_ConsignmentForm> _forms = [_ConsignmentForm()];
  FeeSplit _feeSplit = FeeSplit.split;

  static const _feeHelp = {
    FeeSplit.buyer: 'Buyer covers all fees on top of the item price.',
    FeeSplit.split: 'Fees are shared equally between buyer and seller.',
    FeeSplit.seller: 'Seller absorbs all fees — buyer pays the item price only.',
  };

  @override
  void dispose() {
    for (final f in _forms) {
      f.dispose();
    }
    super.dispose();
  }

  bool get _allComplete => _forms.every((f) => f.isComplete);
  bool get _anyUploading =>
      _forms.any((f) => f.uploadingDispatch || f.uploadingWaybill);

  // New consignment appears stacked below the existing ones.
  void _addConsignment() {
    setState(() => _forms.add(_ConsignmentForm()));
  }

  /// Delete with a confirmation popup; the last consignment can't be removed.
  Future<void> _confirmRemove(int index) async {
    if (_forms.length <= 1) return;
    final remove = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.xl),
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.xl, AppSizes.xl, AppSizes.xl, AppSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Remove consignment ${index + 1}?', style: AppText.h2),
            const SizedBox(height: AppSizes.sm),
            Text(
              'This consignment and everything you entered for it will be removed. This can\'t be undone.',
              style: AppText.body,
            ),
            const SizedBox(height: AppSizes.xl),
            AppButton(
              label: 'Remove consignment',
              icon: Icons.delete_outline_rounded,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            const SizedBox(height: AppSizes.sm),
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.soft,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
          ],
        ),
      ),
    );
    if (remove == true && _forms.length > 1 && index < _forms.length) {
      setState(() {
        _forms.removeAt(index).dispose();
      });
    }
  }

  /// Open Hoppr Vision; if the user confirms a scan, pre-fill the form.
  Future<void> _openVisionScan() async {
    final confirmed = await AppNav.push<bool>(
        context, const ScanVisionScreen());
    if (confirmed == true && mounted) _autofill();
  }

  void _autofill() {
    final f = _forms.first;
    setState(() {
      f.product.text = 'MacBook Pro M2';
      f.amount.text = '1,230,087';
      f.buyer.text = '0901234 5678';
      f.dispatcherName.text = 'Tunde Bello';
      f.dispatcherPhone.text = '+234 706 740 8881';
      f.bank.text = 'GTBank';
      f.account.text = '0123456789';
      f.accountName.text = 'Tunde Bello';
      f.payoutExpanded = true;
    });
    AppSnackbar.info(
        context, 'Demo scan — sample details filled. Review & edit each field.');
  }

  void _continue() {
    // Validate courier account numbers here (where the field lives) so a bad
    // one is caught + focused now, not as a 422 later on Payment Setup.
    for (final f in _forms) {
      if (f.payoutStarted && f.account.text.trim().length != 10) {
        setState(() => f.payoutExpanded = true);
        WidgetsBinding.instance
            .addPostFrameCallback((_) => f.accountFocus.requestFocus());
        AppSnackbar.error(context, 'Account number must be exactly 10 digits.');
        return;
      }
    }
    final consignments = _forms.map((f) => f.toModel()).toList();
    AppNav.push(
      context,
      PaymentSetupScreen(consignments: consignments, feeSplit: _feeSplit),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canRemove = _forms.length > 1;
    return AppScaffold(
      title: 'Create Transaction',
      bottomAction: AppButton(
        label: 'Continue to Payment Setup',
        trailingIcon: Icons.arrow_forward_rounded,
        enabled: _allComplete && !_anyUploading,
        onPressed: _continue,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          _VisionBanner(onTap: _openVisionScan),
          const SizedBox(height: AppSizes.lg),
          // All consignments shown stacked, newest at the bottom.
          for (int i = 0; i < _forms.length; i++) ...[
            _ConsignmentEditor(
              key: ObjectKey(_forms[i]),
              form: _forms[i],
              index: i,
              total: _forms.length,
              onChanged: () => setState(() {}),
              onRemove: canRemove ? () => _confirmRemove(i) : null,
            ),
            const SizedBox(height: AppSizes.lg),
          ],
          // Dashed "Add consignment" tile.
          GestureDetector(
            onTap: _addConsignment,
            behavior: HitTestBehavior.opaque,
            child: DottedBorderBox(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSizes.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_rounded, size: 20),
                    const SizedBox(width: AppSizes.sm),
                    Text('Add consignment', style: AppText.bodyStrong),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          // Who pays the fees?
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Who pays the fees?', style: AppText.h3),
                    ),
                    Text('Delivery & trust', style: AppText.caption),
                  ],
                ),
                const SizedBox(height: AppSizes.md),
                SegmentedControl(
                  segments: const ['Buyer', '50 : 50', 'Seller'],
                  selected: _feeSplit.index,
                  onChanged: (i) =>
                      setState(() => _feeSplit = FeeSplit.values[i]),
                ),
                const SizedBox(height: AppSizes.sm),
                Text(_feeHelp[_feeSplit]!, style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.sm),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class _VisionBanner extends StatelessWidget {
  const _VisionBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Lilac in the Lime theme; neutral accent tint in Mono.
    final accent = AppAccent.of(context);
    return AppCard(
      onTap: onTap,
      color: accent.isLime ? const Color(0xFFDFD9F8) : accent.accentSoft,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.sm,
            ),
            child: Icon(Icons.auto_awesome_rounded,
                size: 20, color: accent.onAccentSoft),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Scan with Hoppr Vision', style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text('Upload a waybill — we auto-fill the fields',
                    style: AppText.caption),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textTertiary),
        ],
      ),
    )
        // Continuous "scan sweep" shimmer hints at the AI capability.
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1800.ms, delay: 1400.ms, color: Colors.white);
  }
}

class _ConsignmentEditor extends ConsumerWidget {
  const _ConsignmentEditor({
    super.key,
    required this.form,
    required this.index,
    required this.total,
    required this.onChanged,
    this.onRemove,
  });

  final _ConsignmentForm form;
  final int index;
  final int total;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  /// Pick an image from the gallery and upload it; store the returned URL on the
  /// form. On failure the picked file is dropped so the user can retry.
  Future<void> _pickPhoto(
      BuildContext context, WidgetRef ref, bool isDispatch) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (picked == null) return;

    if (isDispatch) {
      form.dispatchPhoto = picked;
      form.uploadingDispatch = true;
    } else {
      form.waybillImage = picked;
      form.uploadingWaybill = true;
    }
    onChanged();

    try {
      final url =
          await ref.read(uploadRepositoryProvider).uploadImage(picked.path);
      if (isDispatch) {
        form.dispatchPhotoUrl = url;
      } else {
        form.waybillImageUrl = url;
      }
    } on ApiException catch (e) {
      if (isDispatch) {
        form.dispatchPhoto = null;
      } else {
        form.waybillImage = null;
      }
      if (context.mounted) AppSnackbar.error(context, e.userMessage);
    } finally {
      if (isDispatch) {
        form.uploadingDispatch = false;
      } else {
        form.uploadingWaybill = false;
      }
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      color: const Color(0xFFFFFFFF),
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Consignment ${index + 1} of $total',
                    style: AppText.h3),
              ),
              if (onRemove != null)
                GestureDetector(
                  onTap: onRemove,
                  child: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: AppColors.textTertiary),
                ),
              const SizedBox(width: AppSizes.sm),
              StatusPill(label: '#${index + 1}', dense: true),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          Row(
            children: [
              Expanded(
                child: _UploadBox(
                  label: 'Dispatch Photo',
                  file: form.dispatchPhoto,
                  uploading: form.uploadingDispatch,
                  onTap: () => _pickPhoto(context, ref, true),
                  onClear: () {
                    form.dispatchPhoto = null;
                    form.dispatchPhotoUrl = null;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: _UploadBox(
                  label: 'Waybill Image',
                  file: form.waybillImage,
                  uploading: form.uploadingWaybill,
                  onTap: () => _pickPhoto(context, ref, false),
                  onClear: () {
                    form.waybillImage = null;
                    form.waybillImageUrl = null;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          AppTextField(
            label: 'Product / Item',
            hint: 'MacBook Pro M2',
            icon: Icons.inventory_2_outlined,
            controller: form.product,
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: AppSizes.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Amount (${Money.naira})',
                  hint: '0.00',
                  controller: form.amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsFormatter()],
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: AppTextField(
                  label: 'Buyer contact',
                  hint: '0901234 5678',
                  icon: Icons.person_outline_rounded,
                  controller: form.buyer,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          _CourierPayoutSection(form: form, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _UploadBox extends StatefulWidget {
  const _UploadBox({
    required this.label,
    required this.file,
    required this.onTap,
    required this.onClear,
    this.uploading = false,
  });

  final String label;
  final XFile? file;
  final VoidCallback onTap;
  final VoidCallback onClear;
  final bool uploading;

  @override
  State<_UploadBox> createState() => _UploadBoxState();
}

class _UploadBoxState extends State<_UploadBox> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_UploadBox old) {
    super.didUpdateWidget(old);
    if (old.file?.path != widget.file?.path) _load();
  }

  // Read bytes once (works on mobile + web) and cache for the thumbnail.
  Future<void> _load() async {
    final f = widget.file;
    if (f == null) {
      if (mounted) setState(() => _bytes = null);
      return;
    }
    final b = await f.readAsBytes();
    if (mounted) setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) {
    final has = widget.file != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: widget.onTap,
          // Dotted (dashed) border kept; the empty fill is a soft grey
          // (#F0F1F0) so the box reads against the white card. The dash colour
          // is AppColors.border (same as the encrypted note) and turns green
          // once a photo is attached.
          child: DottedBorderBox(
            active: has,
            fill: has ? null : const Color(0xFFF0F1F0),
            child: SizedBox(
              height: 92,
              child: has
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_bytes != null)
                          Image.memory(_bytes!, fit: BoxFit.cover)
                        else
                          const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        if (widget.uploading)
                          Container(
                            color: Colors.black.withValues(alpha: 0.4),
                            child: const Center(
                                child: AppButtonLoader(color: Colors.white)),
                          ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: GestureDetector(
                            onTap: widget.onClear,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.image_outlined,
                              size: 26, color: AppColors.textTertiary),
                          const SizedBox(height: 6),
                          Text(
                            widget.label,
                            style: AppText.caption.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: AppSizes.sm),
        // Caption row beneath the box (centered): camera icon + label share a
        // single colour so they read as one unit — same on both boxes, and
        // both turn green together once a photo is attached.
        Builder(
          builder: (_) {
            final captionColor =
                has ? AppColors.success : AppColors.textTertiary;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  has
                      ? Icons.check_circle_rounded
                      : Icons.photo_camera_outlined,
                  size: 14,
                  color: captionColor,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.label,
                    style: AppText.caption.copyWith(
                      color: captionColor,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CourierPayoutSection extends StatelessWidget {
  const _CourierPayoutSection({required this.form, required this.onChanged});
  final _ConsignmentForm form;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final payout = form.payoutModel;
    // Accent circle behind the truck icon follows the theme (lime / mono).
    final accent = AppAccent.of(context);
    return AppCard(
      color: const Color(0xFFFBFBFB),
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              form.payoutExpanded = !form.payoutExpanded;
              onChanged();
            },
            borderRadius: AppRadii.sm,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.accentSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.local_shipping_outlined,
                      size: 20, color: accent.onAccentSoft),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Courier Payout Details',
                          style: AppText.h3),
                      const SizedBox(height: 4),
                      Text(
                        payout.isComplete ? payout.summary : 'Add dispatcher payout',
                        style: AppText.caption,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (payout.isComplete)
                  const StatusPill(
                    label: 'Added',
                    icon: Icons.check_rounded,
                    background: AppColors.successSoft,
                    foreground: AppColors.success,
                    dense: true,
                  )
                else
                  const StatusPill(
                    label: 'REQUIRED',
                    background: Color(0xFFECECEC),
                    foreground: AppColors.textPrimary,
                    border: AppColors.border,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    dense: true,
                  ),
                const SizedBox(width: 4),
                Icon(
                  form.payoutExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            duration: AppDurations.normal,
            sizeCurve: AppDurations.easeOut,
            crossFadeState: form.payoutExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: AppSizes.md),
              child: Column(
                children: [
                  AppTextField(
                    label: 'Dispatcher name',
                    hint: 'Tunde Bello',
                    icon: Icons.person_outline_rounded,
                    controller: form.dispatcherName,
                    onChanged: (_) => onChanged(),
                  ),
                  const SizedBox(height: AppSizes.md),
                  AppTextField(
                    label: 'Dispatcher phone',
                    hint: '+234 706 740 8881',
                    icon: Icons.phone_outlined,
                    controller: form.dispatcherPhone,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => onChanged(),
                  ),
                  const SizedBox(height: AppSizes.md),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'Bank',
                          hint: 'Select bank',
                          controller: form.bank,
                          onChanged: (_) => onChanged(),
                        ),
                      ),
                      const SizedBox(width: AppSizes.md),
                      Expanded(
                        child: AppTextField(
                          label: 'Account number',
                          hint: '0000000000',
                          controller: form.account,
                          focusNode: form.accountFocus,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          onChanged: (_) => onChanged(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.md),
                  AppTextField(
                    label: 'Account name',
                    hint: 'As shown on the account',
                    icon: Icons.verified_user_outlined,
                    controller: form.accountName,
                    onChanged: (_) => onChanged(),
                  ),
                  const SizedBox(height: AppSizes.md),
                  // Reassurance note — the courier's bank details are protected.
                  // Matched to the AppTextField styling exactly (same white
                  // fill, border colour, border width and radius) so it sits
                  // flush with the inputs above it.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSizes.lg, vertical: AppSizes.md),
                    decoration: BoxDecoration(
                      // Lilac in the Lime theme; soft grey in Mono.
                      color: accent.isLime
                          ? const Color(0xFFECE9FB)
                          : const Color(0xFFF0F0F0),
                      borderRadius: AppRadii.md,
                      border: Border.all(color: AppColors.border, width: 1.2),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_outline_rounded,
                            size: 15, color: AppColors.textTertiary),
                        const SizedBox(width: AppSizes.sm),
                        Expanded(
                          child: Text(
                            'Payout metadata is encrypted and used only to '
                            'settle the courier once delivery is verified.',
                            style: AppText.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// State holder for one consignment's controllers.
class _ConsignmentForm {
  final product = TextEditingController();
  final amount = TextEditingController();
  final buyer = TextEditingController();
  final dispatcherName = TextEditingController();
  final dispatcherPhone = TextEditingController();
  final bank = TextEditingController();
  final account = TextEditingController();
  final accountName = TextEditingController();
  XFile? dispatchPhoto;
  XFile? waybillImage;
  String? dispatchPhotoUrl; // backend URL once the upload completes
  String? waybillImageUrl;
  bool uploadingDispatch = false;
  bool uploadingWaybill = false;
  bool payoutExpanded = false;
  final accountFocus = FocusNode();

  bool get hasDispatchPhoto => dispatchPhoto != null;
  bool get hasWaybill => waybillImage != null;

  /// True once any courier-payout field has been touched.
  bool get payoutStarted =>
      dispatcherName.text.trim().isNotEmpty ||
      dispatcherPhone.text.trim().isNotEmpty ||
      bank.text.trim().isNotEmpty ||
      account.text.trim().isNotEmpty ||
      accountName.text.trim().isNotEmpty;

  bool get isComplete =>
      product.text.trim().isNotEmpty &&
      amount.text.trim().isNotEmpty &&
      buyer.text.trim().isNotEmpty;

  CourierPayout get payoutModel => CourierPayout(
        dispatcherName: dispatcherName.text.trim(),
        dispatcherPhone: dispatcherPhone.text.trim(),
        bank: bank.text.trim(),
        accountNumber: account.text.trim(),
        accountName: accountName.text.trim(),
      );

  Consignment toModel() => Consignment(
        product: product.text.trim(),
        amount: amount.text.trim(),
        buyerContact: buyer.text.trim(),
        payout: payoutModel,
        hasDispatchPhoto: hasDispatchPhoto,
        hasWaybillImage: hasWaybill,
        dispatchPhotoUrl: dispatchPhotoUrl,
        waybillImageUrl: waybillImageUrl,
      );

  void dispose() {
    for (final c in [
      product,
      amount,
      buyer,
      dispatcherName,
      dispatcherPhone,
      bank,
      account,
      accountName,
    ]) {
      c.dispose();
    }
    accountFocus.dispose();
  }
}
