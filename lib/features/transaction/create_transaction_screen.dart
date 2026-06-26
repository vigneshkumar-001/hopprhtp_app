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
      f.quantity.text = '1';
      f.weight.text = '2.1 kg';
      f.buyerName.text = 'Amara Okafor';
      f.buyerContact.text = '0901234 5678';
      f.deliveryAddress.text = '12 Bode Thomas Street, Surulere, Lagos';
      f.waybillTrackingNumber.text = 'TRK-8839201';
      f.dispatcherName.text = 'Tunde Bello';
      f.dispatcherPhone.text = '+234 706 740 8881';
      f.dispatcherAddress.text = 'Ikeja logistics hub, Lagos';
      f.bank.text = 'GTBank';
      f.account.text = '0123456789';
      f.accountName.text = 'Tunde Bello';
      f.specialInstructions.text = 'Call buyer on arrival.';
      f.payoutExpanded = true;
    });
    AppSnackbar.info(
        context, 'Demo scan — sample details filled. Review & edit each field.');
  }

  void _continue() {
    // Validate mandatory fields here so this guards EVERY entry path — the
    // Continue button AND the account-name field's keyboard "done" action,
    // which calls this directly. We focus + scroll to the first missing field
    // with a specific message instead of silently blocking, and never advance
    // with an incomplete consignment (the backend 422s on the required fields).
    for (int i = 0; i < _forms.length; i++) {
      final f = _forms[i];
      final invalid = f.firstInvalid();
      if (invalid == null) continue;

      if (invalid.inPayout && !f.payoutExpanded) {
        setState(() => f.payoutExpanded = true);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        invalid.focus.requestFocus();
        final ctx = invalid.focus.context;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: AppDurations.normal,
            curve: AppDurations.easeOut,
            alignment: 0.2,
          );
        }
      });
      final prefix = _forms.length > 1 ? 'Consignment ${i + 1}: ' : '';
      AppSnackbar.error(context, '$prefix${invalid.message}');
      return;
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
        // Stays tappable (unless an image is still uploading) so a tap on an
        // incomplete form gives a clear "what's missing" message via _continue,
        // rather than a silently-disabled button.
        enabled: !_anyUploading,
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
              onContinue: _continue,
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
    required this.onContinue,
    this.onRemove,
  });

  final _ConsignmentForm form;
  final int index;
  final int total;
  final VoidCallback onChanged;
  final VoidCallback onContinue;
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
    Widget ordered(double order, Widget child) => FocusTraversalOrder(
          order: NumericFocusOrder(order),
          child: child,
        );
    void focusNext(FocusNode node) => FocusScope.of(context).requestFocus(node);

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
                  label: 'Dispatch photo',
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
                  label: 'Waybill image',
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
          _SectionHeader(title: 'Product / Item Information'),
          const SizedBox(height: AppSizes.md),
          ordered(
            1,
            AppTextField(
              label: 'Product / item',
              hint: 'MacBook Pro M2',
              icon: Icons.inventory_2_outlined,
              controller: form.product,
              focusNode: form.productFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => focusNext(form.amountFocus),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ordered(
                  2,
                  AppTextField(
                    label: 'Amount',
                    prefixText: Money.naira,
                    controller: form.amount,
                    focusNode: form.amountFocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [ThousandsFormatter()],
                    onSubmitted: (_) => focusNext(form.quantityFocus),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: ordered(
                  3,
                  AppTextField(
                    label: 'Quantity',
                    controller: form.quantity,
                    focusNode: form.quantityFocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => focusNext(form.weightFocus),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: ordered(
                  4,
                  AppTextField(
                    label: 'Weight',
                    controller: form.weight,
                    focusNode: form.weightFocus,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => focusNext(form.buyerNameFocus),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          _SectionHeader(title: 'Buyer Information'),
          const SizedBox(height: AppSizes.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ordered(
                  5,
                  AppTextField(
                    label: 'Buyer name',
                    icon: Icons.person_outline_rounded,
                    controller: form.buyerName,
                    focusNode: form.buyerNameFocus,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => focusNext(form.buyerContactFocus),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: ordered(
                  6,
                  AppTextField(
                    label: 'Buyer contact',
                    icon: Icons.phone_outlined,
                    controller: form.buyerContact,
                    focusNode: form.buyerContactFocus,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => focusNext(form.deliveryAddressFocus),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          _SectionHeader(title: 'Delivery Information'),
          const SizedBox(height: AppSizes.md),
          ordered(
            7,
            AppTextField(
              label: 'Delivery address',
              hint: '12 Bode Thomas Street, Surulere, Lagos',
              icon: Icons.location_on_outlined,
              controller: form.deliveryAddress,
              focusNode: form.deliveryAddressFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => focusNext(form.waybillTrackingFocus),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          ordered(
            8,
            AppTextField(
              label: 'Waybill / tracking number',
              hint: 'TRK-8839201',
              icon: Icons.receipt_long_outlined,
              controller: form.waybillTrackingNumber,
              focusNode: form.waybillTrackingFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => focusNext(form.dispatcherNameFocus),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          _SectionHeader(title: 'Dispatcher Information'),
          const SizedBox(height: AppSizes.md),
          ordered(
            9,
            AppTextField(
              label: 'Dispatcher name',
              icon: Icons.person_outline_rounded,
              controller: form.dispatcherName,
              focusNode: form.dispatcherNameFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => focusNext(form.dispatcherPhoneFocus),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(
                child: ordered(
                  10,
                  AppTextField(
                    label: 'Dispatcher phone number',
                    icon: Icons.phone_outlined,
                    controller: form.dispatcherPhone,
                    focusNode: form.dispatcherPhoneFocus,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => focusNext(form.dispatcherAddressFocus),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: ordered(
                  11,
                  AppTextField(
                    label: 'Dispatcher address',
                    icon: Icons.map_outlined,
                    controller: form.dispatcherAddress,
                    focusNode: form.dispatcherAddressFocus,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => focusNext(form.specialInstructionsFocus),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          _SectionHeader(title: 'Additional Information (optional)'),
          const SizedBox(height: AppSizes.md),
          ordered(
            12,
            AppTextField(
              label: 'Special instruction / notes',
              controller: form.specialInstructions,
              focusNode: form.specialInstructionsFocus,
              keyboardType: TextInputType.multiline,
              minLines: 3,
              maxLines: 5,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) {
                form.payoutExpanded = true;
                onChanged();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    FocusScope.of(context).requestFocus(form.bankFocus);
                  }
                });
              },
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          _CourierPayoutSection(
            form: form,
            onChanged: onChanged,
            onContinue: onContinue,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: AppText.h3);
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
  const _CourierPayoutSection({
    required this.form,
    required this.onChanged,
    required this.onContinue,
  });
  final _ConsignmentForm form;
  final VoidCallback onChanged;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final payout = form.payoutModel;
    // Accent circle behind the truck icon follows the theme (lime / mono).
    final accent = AppAccent.of(context);
    Widget ordered(double order, Widget child) => FocusTraversalOrder(
          order: NumericFocusOrder(order),
          child: child,
        );
    void focusNext(FocusNode node) => FocusScope.of(context).requestFocus(node);

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
                  Row(
                    children: [
                      Expanded(
                        child: ordered(
                          13,
                          AppTextField(
                            label: 'Bank name',
                            hint: 'GTBank',
                            icon: Icons.account_balance_outlined,
                            controller: form.bank,
                            focusNode: form.bankFocus,
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => focusNext(form.accountFocus),
                            onChanged: (_) => onChanged(),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSizes.md),
                      Expanded(
                        child: ordered(
                          14,
                          AppTextField(
                            label: 'Account number',
                            hint: '0000000000',
                            controller: form.account,
                            focusNode: form.accountFocus,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            onSubmitted: (_) =>
                                focusNext(form.accountNameFocus),
                            onChanged: (_) => onChanged(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.md),
                  ordered(
                    15,
                    AppTextField(
                      label: 'Account name',
                      hint: 'As shown on the account',
                      icon: Icons.verified_user_outlined,
                      controller: form.accountName,
                      focusNode: form.accountNameFocus,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => onContinue(),
                      onChanged: (_) => onChanged(),
                    ),
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
  final quantity = TextEditingController();
  final weight = TextEditingController();
  final buyerName = TextEditingController();
  final buyerContact = TextEditingController();
  final deliveryAddress = TextEditingController();
  final waybillTrackingNumber = TextEditingController();
  final dispatcherName = TextEditingController();
  final dispatcherPhone = TextEditingController();
  final dispatcherAddress = TextEditingController();
  final bank = TextEditingController();
  final account = TextEditingController();
  final accountName = TextEditingController();
  final specialInstructions = TextEditingController();
  XFile? dispatchPhoto;
  XFile? waybillImage;
  String? dispatchPhotoUrl; // backend URL once the upload completes
  String? waybillImageUrl;
  bool uploadingDispatch = false;
  bool uploadingWaybill = false;
  bool payoutExpanded = false;
  final productFocus = FocusNode();
  final amountFocus = FocusNode();
  final quantityFocus = FocusNode();
  final weightFocus = FocusNode();
  final buyerNameFocus = FocusNode();
  final buyerContactFocus = FocusNode();
  final deliveryAddressFocus = FocusNode();
  final waybillTrackingFocus = FocusNode();
  final dispatcherNameFocus = FocusNode();
  final dispatcherPhoneFocus = FocusNode();
  final dispatcherAddressFocus = FocusNode();
  final specialInstructionsFocus = FocusNode();
  final bankFocus = FocusNode();
  final accountFocus = FocusNode();
  final accountNameFocus = FocusNode();

  bool get hasDispatchPhoto => dispatchPhoto != null;
  bool get hasWaybill => waybillImage != null;

  double get _amountValue =>
      double.tryParse(amount.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  /// The first mandatory field that fails validation, with the focus node to
  /// jump to and the message to show — or null when the consignment is valid.
  /// Field order matches the on-screen order so the user is walked top-to-bottom.
  /// The min/max rules MIRROR the backend Zod schema (transaction.schema.ts) so
  /// a value can never slip through to a server-side 422.
  ({FocusNode focus, String message, bool inPayout})? firstInvalid() {
    ({FocusNode focus, String message, bool inPayout}) err(
            FocusNode f, String m, {bool payout = false}) =>
        (focus: f, message: m, inPayout: payout);

    final productText = product.text.trim();
    if (productText.isEmpty) {
      return err(productFocus, 'Enter the product or item name.');
    }
    if (productText.length > 120) {
      return err(productFocus, 'Product name must be 120 characters or fewer.');
    }

    if (_amountValue <= 0) return err(amountFocus, 'Enter the item amount.');
    if (_amountValue > 1000000000) {
      return err(amountFocus, 'That amount is too large.');
    }

    final qty = quantity.text.trim();
    if (qty.isEmpty) return err(quantityFocus, 'Enter the quantity.');
    if (qty.length > 40) {
      return err(quantityFocus, 'Quantity must be 40 characters or fewer.');
    }

    if (weight.text.trim().length > 40) {
      return err(weightFocus, 'Weight must be 40 characters or fewer.');
    }

    final bName = buyerName.text.trim();
    if (bName.isEmpty) return err(buyerNameFocus, "Enter the buyer's name.");
    if (bName.length > 120) {
      return err(buyerNameFocus, 'Buyer name must be 120 characters or fewer.');
    }

    final bContact = buyerContact.text.trim();
    if (bContact.length < 3) {
      return err(buyerContactFocus,
          'Enter a valid buyer contact (at least 3 characters).');
    }
    if (bContact.length > 120) {
      return err(
          buyerContactFocus, 'Buyer contact must be 120 characters or fewer.');
    }

    final addr = deliveryAddress.text.trim();
    if (addr.isEmpty) return err(deliveryAddressFocus, 'Enter the delivery address.');
    if (addr.length > 240) {
      return err(deliveryAddressFocus,
          'Delivery address must be 240 characters or fewer.');
    }

    if (waybillTrackingNumber.text.trim().length > 80) {
      return err(waybillTrackingFocus,
          'Waybill / tracking number must be 80 characters or fewer.');
    }

    final dName = dispatcherName.text.trim();
    if (dName.length < 2) {
      return err(dispatcherNameFocus,
          "Enter the dispatcher's name (at least 2 characters).");
    }
    if (dName.length > 80) {
      return err(
          dispatcherNameFocus, 'Dispatcher name must be 80 characters or fewer.');
    }

    final dPhone = dispatcherPhone.text.trim();
    if (dPhone.length < 7) {
      return err(dispatcherPhoneFocus,
          'Enter a valid dispatcher phone (at least 7 digits).');
    }
    if (dPhone.length > 20) {
      return err(dispatcherPhoneFocus,
          'Dispatcher phone must be 20 characters or fewer.');
    }

    if (dispatcherAddress.text.trim().length > 240) {
      return err(dispatcherAddressFocus,
          'Dispatcher address must be 240 characters or fewer.');
    }

    if (specialInstructions.text.trim().length > 500) {
      return err(specialInstructionsFocus,
          'Notes must be 500 characters or fewer.');
    }

    final bankText = bank.text.trim();
    if (bankText.length < 2) {
      return err(bankFocus, "Enter the courier's bank name.", payout: true);
    }
    if (bankText.length > 60) {
      return err(bankFocus, 'Bank name must be 60 characters or fewer.',
          payout: true);
    }

    if (!RegExp(r'^\d{10}$').hasMatch(account.text.trim())) {
      return err(accountFocus, 'Account number must be exactly 10 digits.',
          payout: true);
    }

    final acctName = accountName.text.trim();
    if (acctName.length < 2) {
      return err(accountNameFocus, "Enter the courier's account name.",
          payout: true);
    }
    if (acctName.length > 80) {
      return err(accountNameFocus, 'Account name must be 80 characters or fewer.',
          payout: true);
    }

    return null;
  }

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
        quantity: quantity.text.trim(),
        weight: weight.text.trim(),
        buyerName: buyerName.text.trim(),
        buyerContact: buyerContact.text.trim(),
        deliveryAddress: deliveryAddress.text.trim(),
        waybillTrackingNumber: waybillTrackingNumber.text.trim(),
        dispatcherAddress: dispatcherAddress.text.trim(),
        specialInstructions: specialInstructions.text.trim(),
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
      quantity,
      weight,
      buyerName,
      buyerContact,
      deliveryAddress,
      waybillTrackingNumber,
      dispatcherName,
      dispatcherPhone,
      dispatcherAddress,
      bank,
      account,
      accountName,
      specialInstructions,
    ]) {
      c.dispose();
    }
    for (final node in [
      productFocus,
      amountFocus,
      quantityFocus,
      weightFocus,
      buyerNameFocus,
      buyerContactFocus,
      deliveryAddressFocus,
      waybillTrackingFocus,
      dispatcherNameFocus,
      dispatcherPhoneFocus,
      dispatcherAddressFocus,
      specialInstructionsFocus,
      bankFocus,
      accountFocus,
      accountNameFocus,
    ]) {
      node.dispose();
    }
  }
}
