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
import '../../core/utils/delivery_fee_estimator.dart';
import '../../core/utils/formatters.dart';
import '../../data/dto/scan_dto.dart';
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
import 'address_picker_screen.dart';
import 'create_transaction_gate.dart';
import 'payment_setup_screen.dart';
import 'scan_vision_screen.dart';

/// Create Transaction (mockup 8). Supports multiple consignments, a "Hoppr
/// Vision" auto-fill shortcut, image-upload placeholders and courier payout.
class CreateTransactionScreen extends ConsumerStatefulWidget {
  const CreateTransactionScreen({super.key});

  @override
  ConsumerState<CreateTransactionScreen> createState() =>
      _CreateTransactionScreenState();
}

class _CreateTransactionScreenState
    extends ConsumerState<CreateTransactionScreen> {
  final List<_ConsignmentForm> _forms = [_ConsignmentForm()];

  // Delivery method — "who delivers?" — a single, transaction-level choice,
  // rendered once after Buyer/Delivery Information (not per consignment).
  // Null means "not chosen yet" — there is deliberately no default; the
  // seller must make an explicit choice before Continue proceeds (see
  // _continue()). The Dispatcher Information section (name/phone/address,
  // bound to the primary consignment) is only shown/required once this is
  // requestDispatcher. There is no separate top-level dispatcher name/phone
  // field: the same Dispatcher Information fields serve both the Hoppr
  // dispatcher account link and the on-screen contact details, never a
  // duplicate pair.
  DeliveryMethod? _deliveryMethod;

  // Platform Fee Payer — "who pays Hoppr Platform Fee?" — a SEPARATE decision
  // from [_deliveryMethod]. Even "Deliver myself" still incurs the fee, since
  // Hoppr still provides the payment link, escrow protection, buyer payment
  // holding, delivery confirmation, dispute safety and seller wallet release.
  // Null means "not chosen yet" — no default, required before Continue (see
  // _continue()).
  PlatformFeePayer? _platformFeePayer;

  @override
  void initState() {
    super.initState();
    // Run after the first real frame so the screen is genuinely on-screen
    // (never a blank placeholder) before the gate can show its blur sheet
    // on top of it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) runCreateTransactionVerificationGate(context, ref);
    });
  }

  @override
  void dispose() {
    for (final f in _forms) {
      f.dispose();
    }
    super.dispose();
  }

  bool get _anyUploading => _forms.any(
    (f) => f.uploadingProduct || f.uploadingDispatch || f.uploadingWaybill,
  );

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
          AppSizes.xl,
          AppSizes.xl,
          AppSizes.xl,
          AppSizes.lg,
        ),
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

  /// Open Hoppr Vision; if the user confirms a scan, apply whatever it
  /// actually detected to the first consignment (never a fabricated value —
  /// see [_applyScanResult]).
  Future<void> _openVisionScan() async {
    final result = await AppNav.push<ScanResult>(
      context,
      const ScanVisionScreen(),
    );
    if (result != null && mounted) await _applyScanResult(result);
  }

  /// Applies Hoppr Vision's detected fields to the first consignment. Fields
  /// left blank on the form are filled silently; fields the user already
  /// typed something into are never overwritten without an explicit choice —
  /// if any would conflict, one confirmation dialog covers all of them.
  Future<void> _applyScanResult(ScanResult result) async {
    final f = _forms.first;
    final notes = [
      result.fields.itemDescription,
      result.fields.packageNotes,
    ].where((v) => (v ?? '').trim().isNotEmpty).join(' — ');

    final planned =
        <(String label, TextEditingController controller, String value)>[
          if ((result.fields.itemName ?? '').trim().isNotEmpty)
            ('Product / Item', f.product, result.fields.itemName!.trim()),
          if ((result.fields.buyerName ?? '').trim().isNotEmpty)
            ('Buyer name', f.buyerName, result.fields.buyerName!.trim()),
          if ((result.fields.buyerPhone ?? '').trim().isNotEmpty)
            ('Buyer contact', f.buyerContact, result.fields.buyerPhone!.trim()),
          if ((result.fields.dispatcherPhone ?? '').trim().isNotEmpty)
            (
              'Dispatcher phone number',
              f.dispatcherPhone,
              result.fields.dispatcherPhone!.trim(),
            ),
          if (result.fields.amount != null)
            ('Amount', f.amount, result.fields.amount!.toStringAsFixed(2)),
          if ((result.fields.deliveryAddress ?? '').trim().isNotEmpty)
            (
              'Delivery address',
              f.deliveryAddress,
              result.fields.deliveryAddress!.trim(),
            ),
          if ((result.fields.pickupAddress ?? '').trim().isNotEmpty)
            (
              'Package Collection Address',
              f.dispatcherAddress,
              result.fields.pickupAddress!.trim(),
            ),
          if ((result.fields.estimatedDelivery ?? '').trim().isNotEmpty)
            (
              'Estimated delivery date',
              f.estimatedDeliveryDate,
              result.fields.estimatedDelivery!.trim(),
            ),
          if (notes.isNotEmpty)
            ('Special instruction / notes', f.specialInstructions, notes),
        ];

    if (planned.isEmpty) {
      if (mounted) {
        AppSnackbar.info(
          context,
          "Hoppr Vision didn't detect any fields from that photo. Please "
          'enter the details manually.',
        );
      }
      return;
    }

    final conflicts = [
      for (final p in planned)
        if (p.$2.text.trim().isNotEmpty && p.$2.text.trim() != p.$3) p.$1,
    ];

    var overwrite = true;
    if (conflicts.isNotEmpty && mounted) {
      overwrite =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Overwrite entered details?'),
              content: Text(
                "You've already entered: ${conflicts.join(', ')}. Replace "
                'them with the scanned values, or keep what you typed?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Keep my entries'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Overwrite'),
                ),
              ],
            ),
          ) ??
          false;
    }

    var filled = 0;
    setState(() {
      for (final (_, controller, value) in planned) {
        final isConflict =
            controller.text.trim().isNotEmpty &&
            controller.text.trim() != value;
        if (isConflict && !overwrite) continue;
        controller.text = value;
        filled++;
        // A detected dispatcher phone is useless while the Dispatcher
        // Information section is hidden behind "Deliver myself" — switch so
        // the seller sees it (still free to switch back, nothing is
        // submitted yet).
        if (controller == f.dispatcherPhone) {
          _deliveryMethod = DeliveryMethod.requestDispatcher;
        }
      }
    });

    if (!mounted) return;
    AppSnackbar.success(
      context,
      'Filled $filled field${filled == 1 ? '' : 's'} from your scan. Review '
      'before continuing.',
    );
  }

  Future<void> _pickDeliveryAddress(_ConsignmentForm form) async {
    final picked = await AppNav.push<AddressPickResult>(
      context,
      AddressPickerScreen(initialAddress: form.deliveryAddress.text.trim()),
    );
    if (picked == null || !mounted) return;
    setState(() {
      form.deliveryAddress.text = picked.address;
      form.deliveryLat = picked.location.latitude;
      form.deliveryLng = picked.location.longitude;
    });
  }

  Future<void> _pickDispatcherAddress(_ConsignmentForm form) async {
    final picked = await AppNav.push<AddressPickResult>(
      context,
      AddressPickerScreen(initialAddress: form.dispatcherAddress.text.trim()),
    );
    if (picked == null || !mounted) return;
    setState(() {
      form.dispatcherAddress.text = picked.address;
      // Required for the backend to calculate the HTP Delivery Fee (distance
      // between this and the delivery address) — previously discarded here,
      // which silently forced every Hoppr Dispatcher transaction into a
      // missing-coordinates state.
      form.dispatcherLat = picked.location.latitude;
      form.dispatcherLng = picked.location.longitude;
    });
  }

  Future<void> _pickEstimatedDeliveryDate(_ConsignmentForm form) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null || !mounted) return;
    setState(() {
      form.estimatedDeliveryDate.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _pickEstimatedDeliveryTime(_ConsignmentForm form) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked == null || !mounted) return;
    final localizations = MaterialLocalizations.of(context);
    setState(() {
      form.estimatedDeliveryTime.text = localizations.formatTimeOfDay(
        picked,
        alwaysUse24HourFormat: false,
      );
    });
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

    final deliveryMethod = _deliveryMethod;
    if (deliveryMethod == null) {
      AppSnackbar.error(context, 'Please select a delivery method');
      return;
    }

    final platformFeePayer = _platformFeePayer;
    if (platformFeePayer == null) {
      AppSnackbar.error(context, 'Please select who pays Hoppr Platform Fee');
      return;
    }

    if (deliveryMethod == DeliveryMethod.requestDispatcher) {
      final primary = _forms.first;
      final invalid = primary.firstInvalidDispatcherField();
      if (invalid != null) {
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
        AppSnackbar.error(context, invalid.message);
        return;
      }
    }

    final consignments = _forms.map((f) => f.toModel()).toList();
    AppNav.push(
      context,
      PaymentSetupScreen(
        consignments: consignments,
        deliveryMethod: deliveryMethod,
        platformFeePayer: platformFeePayer,
      ),
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
              onPickDeliveryAddress: (form) => _pickDeliveryAddress(form),
              onPickEstimatedDeliveryDate: (form) =>
                  _pickEstimatedDeliveryDate(form),
              onPickEstimatedDeliveryTime: (form) =>
                  _pickEstimatedDeliveryTime(form),
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
          // Who physically handles pickup + delivery — immediately after
          // Buyer/Delivery Information, before the dispatcher-conditional
          // section it gates. No default: the seller must choose explicitly
          // (see _continue()'s "Please select a delivery method" check).
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Delivery method', style: AppText.h3),
                const SizedBox(height: AppSizes.md),
                SegmentedControl(
                  segments: const ['Deliver myself', 'Hoppr Dispatcher'],
                  selected: _deliveryMethod?.index ?? -1,
                  onChanged: (i) => setState(
                    () => _deliveryMethod = DeliveryMethod.values[i],
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
                Text(switch (_deliveryMethod) {
                  null =>
                    'Choose who will handle pickup and delivery for this order.',
                  DeliveryMethod.sellerSelf =>
                    "You'll handle pickup and delivery yourself — no dispatcher needed.",
                  DeliveryMethod.requestDispatcher =>
                    'Enter your dispatcher below. They\'ll be notified once '
                        'payment is secured.',
                }, style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          // Who pays Hoppr Platform Fee — a SEPARATE decision from delivery
          // method (see field doc comment above). Applies regardless of
          // whether the seller delivers themselves or requests a Hoppr
          // Dispatcher: Hoppr still provides the payment link, escrow
          // protection, buyer payment holding, delivery confirmation, dispute
          // safety and seller wallet release either way. No default: the
          // seller must choose explicitly (see _continue()'s "Please select
          // who pays Hoppr Platform Fee" check).
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Who pays Hoppr Platform Fee?', style: AppText.h3),
                const SizedBox(height: AppSizes.md),
                SegmentedControl(
                  segments: const ['Buyer', '50:50', 'Seller'],
                  selected: _platformFeePayer?.index ?? -1,
                  onChanged: (i) => setState(
                    () => _platformFeePayer = PlatformFeePayer.values[i],
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
                Text(switch (_platformFeePayer) {
                  null =>
                    'Hoppr still provides escrow protection and delivery '
                        'confirmation even if you deliver it yourself — '
                        'choose who covers the platform fee.',
                  PlatformFeePayer.buyer =>
                    'The buyer pays the platform fee on top of the item price.',
                  PlatformFeePayer.seller =>
                    'You absorb the platform fee — the buyer pays the item '
                        'price only.',
                  PlatformFeePayer.split50 =>
                    'The platform fee is split equally between you and the '
                        'buyer.',
                }, style: AppText.caption),
              ],
            ),
          ),
          if (_deliveryMethod == DeliveryMethod.requestDispatcher) ...[
            const SizedBox(height: AppSizes.md),
            _DispatcherSection(
              form: _forms.first,
              onChanged: () => setState(() {}),
              onContinue: _continue,
              onPickDispatcherAddress: () =>
                  _pickDispatcherAddress(_forms.first),
            ),
          ],
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
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: accent.onAccentSoft,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Scan with Hoppr Vision', style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      'Upload a waybill — we auto-fill the fields',
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        )
        // Continuous "scan sweep" shimmer hints at the AI capability.
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1800.ms, delay: 1400.ms, color: Colors.white);
  }
}

/// The three independent photo slots on a consignment. Each maps to its own
/// backend field: product → productPhotoUrl, dispatch → dispatchPhotoUrl,
/// waybill → waybillImageUrl.
enum _PhotoSlot { product, dispatch, waybill }

class _ConsignmentEditor extends ConsumerWidget {
  const _ConsignmentEditor({
    super.key,
    required this.form,
    required this.index,
    required this.total,
    required this.onChanged,
    required this.onPickDeliveryAddress,
    required this.onPickEstimatedDeliveryDate,
    required this.onPickEstimatedDeliveryTime,
    this.onRemove,
  });

  final _ConsignmentForm form;
  final int index;
  final int total;
  final VoidCallback onChanged;
  final Future<void> Function(_ConsignmentForm form) onPickDeliveryAddress;
  final Future<void> Function(_ConsignmentForm form)
  onPickEstimatedDeliveryDate;
  final Future<void> Function(_ConsignmentForm form)
  onPickEstimatedDeliveryTime;
  final VoidCallback? onRemove;

  /// Bottom sheet to pick the image source: Take Photo / Choose from Gallery /
  /// Cancel. Returns null when cancelled/dismissed.
  Future<ImageSource?> _chooseImageSource(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(AppSizes.sm),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.xl,
          ),
          padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text('Take Photo', style: AppText.bodyStrong),
                onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text('Choose from Gallery', style: AppText.bodyStrong),
                onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: Text(
                  'Cancel',
                  style: AppText.body.copyWith(color: AppColors.textSecondary),
                ),
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pick an image (camera or gallery) and upload it; store the returned URL on
  /// the form for the given [slot]. On failure the picked file is dropped so the
  /// user can retry, and a clear error is shown — never a false success.
  Future<void> _pickPhoto(
    BuildContext context,
    WidgetRef ref,
    _PhotoSlot slot,
  ) async {
    final source = await _chooseImageSource(context);
    if (source == null) return; // cancelled

    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(
          context,
          source == ImageSource.camera
              ? 'Could not open the camera. Please try again.'
              : 'Could not open the gallery. Please try again.',
        );
      }
      return;
    }
    if (picked == null) return;

    switch (slot) {
      case _PhotoSlot.product:
        form.productPhoto = picked;
        form.uploadingProduct = true;
      case _PhotoSlot.dispatch:
        form.dispatchPhoto = picked;
        form.uploadingDispatch = true;
      case _PhotoSlot.waybill:
        form.waybillImage = picked;
        form.uploadingWaybill = true;
    }
    onChanged();

    try {
      final url = await ref
          .read(uploadRepositoryProvider)
          .uploadImage(picked.path);
      switch (slot) {
        case _PhotoSlot.product:
          form.productPhotoUrl = url;
        case _PhotoSlot.dispatch:
          form.dispatchPhotoUrl = url;
        case _PhotoSlot.waybill:
          form.waybillImageUrl = url;
      }
    } on ApiException catch (e) {
      switch (slot) {
        case _PhotoSlot.product:
          form.productPhoto = null;
        case _PhotoSlot.dispatch:
          form.dispatchPhoto = null;
        case _PhotoSlot.waybill:
          form.waybillImage = null;
      }
      if (context.mounted) AppSnackbar.error(context, e.userMessage);
    } finally {
      switch (slot) {
        case _PhotoSlot.product:
          form.uploadingProduct = false;
        case _PhotoSlot.dispatch:
          form.uploadingDispatch = false;
        case _PhotoSlot.waybill:
          form.uploadingWaybill = false;
      }
      onChanged();
    }
  }

  /// One labelled photo card: persistent title + helper text above the upload
  /// box (which itself carries the preview / check / remove states).
  Widget _photoField({
    required String title,
    required String helper,
    required Widget box,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.bodyStrong),
        const SizedBox(height: 2),
        Text(helper, style: AppText.caption),
        const SizedBox(height: AppSizes.sm),
        box,
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget ordered(double order, Widget child) =>
        FocusTraversalOrder(order: NumericFocusOrder(order), child: child);
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
                child: Text(
                  'Consignment ${index + 1} of $total',
                  style: AppText.h3,
                ),
              ),
              if (onRemove != null)
                GestureDetector(
                  onTap: onRemove,
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                ),
              const SizedBox(width: AppSizes.sm),
              StatusPill(label: '#${index + 1}', dense: true),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          // Product photo — the item being sold — as its own large top card.
          _SectionHeader(title: 'Product Photo'),
          const SizedBox(height: AppSizes.sm),
          Text(
            'Upload clear photos of the item you are selling.',
            style: AppText.caption,
          ),
          const SizedBox(height: AppSizes.sm),
          _UploadBox(
            label: 'Product Photo',
            file: form.productPhoto,
            uploading: form.uploadingProduct,
            onTap: () => _pickPhoto(context, ref, _PhotoSlot.product),
            onClear: () {
              form.productPhoto = null;
              form.productPhotoUrl = null;
              onChanged();
            },
          ),
          const SizedBox(height: AppSizes.lg),
          // Dispatch + Waybill proof photos, side by side. Each is optional and
          // saved to its own backend field (dispatchPhotoUrl / waybillImageUrl).
          _SectionHeader(title: 'Proof Photos'),
          const SizedBox(height: AppSizes.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _photoField(
                  title: 'Dispatch Photo',
                  helper: 'Package/dispatch proof.',
                  box: _UploadBox(
                    label: 'Dispatch Photo',
                    file: form.dispatchPhoto,
                    uploading: form.uploadingDispatch,
                    onTap: () => _pickPhoto(context, ref, _PhotoSlot.dispatch),
                    onClear: () {
                      form.dispatchPhoto = null;
                      form.dispatchPhotoUrl = null;
                      onChanged();
                    },
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: _photoField(
                  title: 'Waybill Photo',
                  helper: 'Courier receipt or label.',
                  box: _UploadBox(
                    label: 'Waybill Photo',
                    file: form.waybillImage,
                    uploading: form.uploadingWaybill,
                    onTap: () => _pickPhoto(context, ref, _PhotoSlot.waybill),
                    onClear: () {
                      form.waybillImage = null;
                      form.waybillImageUrl = null;
                      onChanged();
                    },
                  ),
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
              required: true,
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
          ordered(
            2,
            AppTextField(
              label: 'Amount',
              required: true,
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
          const SizedBox(height: AppSizes.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ordered(
                  3,
                  AppTextField(
                    label: 'Quantity',
                    required: true,
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppTextField(
                        label: 'Package Weight',
                        required: false,
                        hint: '0.0',
                        controller: form.weight,
                        focusNode: form.weightFocus,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        trailing: Text(
                          'kg',
                          style: AppText.bodyStrong.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => focusNext(form.buyerNameFocus),
                        onChanged: (_) => onChanged(),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Enter package weight in kilograms.',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          _SectionHeader(title: 'Buyer Information'),
          const SizedBox(height: AppSizes.md),
          ordered(
            5,
            AppTextField(
              label: 'Buyer name',
              required: true,
              icon: Icons.person_outline_rounded,
              controller: form.buyerName,
              focusNode: form.buyerNameFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => focusNext(form.buyerContactFocus),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          ordered(
            6,
            AppTextField(
              label: 'Buyer contact',
              required: true,
              icon: Icons.phone_outlined,
              controller: form.buyerContact,
              focusNode: form.buyerContactFocus,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => focusNext(form.deliveryAddressFocus),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          _SectionHeader(title: 'Delivery Information'),
          const SizedBox(height: AppSizes.md),
          ordered(
            7,
            _LargeAddressField(
              label: 'Delivery address',
              required: true,
              icon: Icons.location_on_outlined,
              value: form.deliveryAddress.text.trim(),
              hint: 'Tap to select delivery address on map',
              onTap: () => onPickDeliveryAddress(form),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          const SizedBox(height: AppSizes.md),
          AppTextField(
            label: 'Estimated delivery date',
            hint: 'Tap to pick a date',
            controller: form.estimatedDeliveryDate,
            focusNode: form.estimatedDeliveryDateFocus,
            required: true,
            readOnly: true,
            onTap: () => onPickEstimatedDeliveryDate(form),
          ),
          const SizedBox(height: AppSizes.md),
          AppTextField(
            label: 'Estimated delivery time',
            hint: 'Optional - tap to pick a time',
            controller: form.estimatedDeliveryTime,
            focusNode: form.estimatedDeliveryTimeFocus,
            required: false,
            readOnly: true,
            onTap: () => onPickEstimatedDeliveryTime(form),
          ),
          const SizedBox(height: AppSizes.md),
          ordered(
            8,
            AppTextField(
              label: 'Waybill / Tracking Number',
              hint: 'TRK-8839201',
              icon: Icons.receipt_long_outlined,
              controller: form.waybillTrackingNumber,
              focusNode: form.waybillTrackingFocus,
              textInputAction: TextInputAction.done,
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Enter the tracking number from your courier receipt or shipping "
            "label after dispatch. Don't have it yet? You can add it later "
            "from Start Delivery / Dispatch Proof once the courier gives it "
            'to you.',
            style: AppText.caption,
          ),
          // Dispatcher Information is transaction-level, not per-consignment
          // — see _CreateTransactionScreenState.build(), which renders it
          // once, after the Delivery Method selector. No payout/bank details
          // are ever collected here — see Payout Accounts / Wallet.
        ],
      ),
    );
  }
}

/// Hoppr Dispatcher fields (name/phone/Package Collection Address) +
/// Additional Information — rendered once per transaction (bound to the
/// primary consignment), only when Delivery Method is requestDispatcher. No
/// payout/bank details — dispatcher settlement happens later via Dispatcher
/// Wallet / Payout Accounts. See _CreateTransactionScreenState.build().
class _DispatcherSection extends StatelessWidget {
  const _DispatcherSection({
    required this.form,
    required this.onChanged,
    required this.onContinue,
    required this.onPickDispatcherAddress,
  });

  final _ConsignmentForm form;
  final VoidCallback onChanged;
  final VoidCallback onContinue;
  final VoidCallback onPickDispatcherAddress;

  @override
  Widget build(BuildContext context) {
    void focusNext(FocusNode node) => FocusScope.of(context).requestFocus(node);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(title: 'Dispatcher Information'),
              const SizedBox(height: AppSizes.md),
              AppTextField(
                label: 'Dispatcher name',
                required: true,
                icon: Icons.person_outline_rounded,
                controller: form.dispatcherName,
                focusNode: form.dispatcherNameFocus,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => focusNext(form.dispatcherPhoneFocus),
                onChanged: (_) => onChanged(),
              ),
              const SizedBox(height: AppSizes.md),
              AppTextField(
                label: 'Dispatcher phone number',
                required: true,
                icon: Icons.phone_outlined,
                controller: form.dispatcherPhone,
                focusNode: form.dispatcherPhoneFocus,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                onChanged: (_) => onChanged(),
              ),
              const SizedBox(height: AppSizes.md),
              _LargeAddressField(
                label: 'Package Collection Address',
                required: true,
                icon: Icons.map_outlined,
                value: form.dispatcherAddress.text.trim(),
                hint: 'Tap to select the collection address on map',
                onTap: onPickDispatcherAddress,
              ),
              const SizedBox(height: AppSizes.lg),
              _SectionHeader(title: 'Additional Information (optional)'),
              const SizedBox(height: AppSizes.md),
              AppTextField(
                label: 'Special instruction / notes',
                controller: form.specialInstructions,
                focusNode: form.specialInstructionsFocus,
                keyboardType: TextInputType.multiline,
                minLines: 3,
                maxLines: 5,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onContinue(),
                onChanged: (_) => onChanged(),
              ),
            ],
          ),
        ),
      ],
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

class _LargeAddressField extends StatelessWidget {
  const _LargeAddressField({
    required this.label,
    required this.icon,
    required this.value,
    required this.hint,
    required this.onTap,
    this.required = false,
  });

  final String label;
  final IconData icon;
  final String value;
  final String hint;
  final VoidCallback onTap;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final hasValue = value.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: AppText.label),
            if (required)
              Text(
                ' *',
                style: AppText.label.copyWith(color: AppColors.danger),
              ),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        AppCard(
          onTap: onTap,
          padding: const EdgeInsets.all(AppSizes.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: AppRadii.sm,
                ),
                child: Icon(icon, size: 20, color: AppColors.textSecondary),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasValue ? value : hint,
                      style: AppText.bodyStrong.copyWith(
                        color: hasValue
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hasValue ? 'Tap to change on map' : 'Tap to open map',
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ],
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        if (widget.uploading)
                          Container(
                            color: Colors.black.withValues(alpha: 0.4),
                            child: const Center(
                              child: AppButtonLoader(color: Colors.white),
                            ),
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
                              child: const Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.image_outlined,
                            size: 26,
                            color: AppColors.textTertiary,
                          ),
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
            final captionColor = has
                ? AppColors.success
                : AppColors.textTertiary;
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

/// State holder for one consignment's controllers.
class _ConsignmentForm {
  final product = TextEditingController();
  final amount = TextEditingController();
  final quantity = TextEditingController();
  final weight = TextEditingController();
  final buyerName = TextEditingController();
  final buyerContact = TextEditingController();
  final deliveryAddress = TextEditingController();
  double? deliveryLat;
  double? deliveryLng;
  final estimatedDeliveryDate = TextEditingController();
  final estimatedDeliveryTime = TextEditingController();
  final waybillTrackingNumber = TextEditingController();
  final dispatcherName = TextEditingController();
  final dispatcherPhone = TextEditingController();
  final dispatcherAddress = TextEditingController();
  double? dispatcherLat;
  double? dispatcherLng;
  final specialInstructions = TextEditingController();
  XFile? productPhoto;
  XFile? dispatchPhoto;
  XFile? waybillImage;
  String? productPhotoUrl; // backend URL once the upload completes
  String? dispatchPhotoUrl;
  String? waybillImageUrl;
  bool uploadingProduct = false;
  bool uploadingDispatch = false;
  bool uploadingWaybill = false;
  final productFocus = FocusNode();
  final amountFocus = FocusNode();
  final quantityFocus = FocusNode();
  final weightFocus = FocusNode();
  final buyerNameFocus = FocusNode();
  final buyerContactFocus = FocusNode();
  final deliveryAddressFocus = FocusNode();
  final estimatedDeliveryDateFocus = FocusNode();
  final estimatedDeliveryTimeFocus = FocusNode();
  final waybillTrackingFocus = FocusNode();
  final dispatcherNameFocus = FocusNode();
  final dispatcherPhoneFocus = FocusNode();
  final dispatcherAddressFocus = FocusNode();
  final specialInstructionsFocus = FocusNode();

  bool get hasDispatchPhoto => dispatchPhoto != null;
  bool get hasWaybill => waybillImage != null;

  /// The weight field only ever holds a plain number — the "kg" unit is a
  /// fixed suffix shown in the UI, not part of the editable text — so it's
  /// appended once here to keep the backend/downstream value unambiguous
  /// (e.g. "2.1" -> "2.1 kg").
  String get _weightWithUnit {
    final w = weight.text.trim();
    return w.isEmpty ? w : '$w kg';
  }

  double get _amountValue =>
      double.tryParse(amount.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  /// The first mandatory field that fails validation, with the focus node to
  /// jump to and the message to show — or null when the consignment is valid.
  /// Field order matches the on-screen order so the user is walked top-to-bottom.
  /// The min/max rules MIRROR the backend Zod schema (transaction.schema.ts) so
  /// a value can never slip through to a server-side 422.
  ({FocusNode focus, String message})? firstInvalid() {
    ({FocusNode focus, String message}) err(FocusNode f, String m) =>
        (focus: f, message: m);

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

    final weightText = weight.text.trim();
    if (weightText.isNotEmpty) {
      final w = double.tryParse(weightText);
      if (w == null) {
        return err(weightFocus, 'Enter a valid numeric weight in kilograms.');
      }
      if (w <= 0) {
        return err(weightFocus, 'Weight must be greater than 0.');
      }
      if (w > 100000) {
        return err(
          weightFocus,
          'That weight looks too large — check the value.',
        );
      }
    }

    final bName = buyerName.text.trim();
    if (bName.isEmpty) return err(buyerNameFocus, "Enter the buyer's name.");
    if (bName.length > 120) {
      return err(buyerNameFocus, 'Buyer name must be 120 characters or fewer.');
    }

    final bContact = buyerContact.text.trim();
    if (bContact.length < 3) {
      return err(
        buyerContactFocus,
        'Enter a valid buyer contact (at least 3 characters).',
      );
    }
    if (bContact.length > 120) {
      return err(
        buyerContactFocus,
        'Buyer contact must be 120 characters or fewer.',
      );
    }

    final addr = deliveryAddress.text.trim();
    final estDate = estimatedDeliveryDate.text.trim();
    if (estDate.isEmpty)
      return err(
        estimatedDeliveryDateFocus,
        "Enter the estimated delivery date.",
      );
    if (addr.isEmpty)
      return err(deliveryAddressFocus, 'Enter the delivery address.');
    if (addr.length > 240) {
      return err(
        deliveryAddressFocus,
        'Delivery address must be 240 characters or fewer.',
      );
    }

    if (waybillTrackingNumber.text.trim().length > 80) {
      return err(
        waybillTrackingFocus,
        'Waybill / tracking number must be 80 characters or fewer.',
      );
    }

    return null;
  }

  /// Dispatcher Information — only asked for (and only required) when a
  /// Hoppr Dispatcher is requested, and only on the primary consignment (that
  /// section renders once per transaction, not per item — see
  /// _CreateTransactionScreenState.build()). The caller decides whether to
  /// call this at all based on the chosen delivery method. Deliberately does
  /// not ask for any payout/bank details — see Consignment/CourierPayout
  /// removal: dispatcher payout is handled later via Dispatcher Wallet /
  /// Admin Settlement, never collected here.
  ({FocusNode focus, String message})? firstInvalidDispatcherField() {
    ({FocusNode focus, String message}) err(FocusNode f, String m) =>
        (focus: f, message: m);

    final dName = dispatcherName.text.trim();
    if (dName.length < 2) {
      return err(
        dispatcherNameFocus,
        "Enter the dispatcher's name (at least 2 characters).",
      );
    }
    if (dName.length > 80) {
      return err(
        dispatcherNameFocus,
        'Dispatcher name must be 80 characters or fewer.',
      );
    }

    final dPhone = dispatcherPhone.text.trim();
    if (dPhone.length < 7) {
      return err(
        dispatcherPhoneFocus,
        'Enter a valid dispatcher phone (at least 7 digits).',
      );
    }
    if (dPhone.length > 20) {
      return err(
        dispatcherPhoneFocus,
        'Dispatcher phone must be 20 characters or fewer.',
      );
    }

    final dAddress = dispatcherAddress.text.trim();
    if (dAddress.isEmpty) {
      return err(
        dispatcherAddressFocus,
        'Enter the package collection address.',
      );
    }
    if (dAddress.length > 240) {
      return err(
        dispatcherAddressFocus,
        'Package Collection Address must be 240 characters or fewer.',
      );
    }
    // The HTP Delivery Fee is calculated from map coordinates, not the
    // address text — the field is map-picker-only (see _LargeAddressField
    // above), so this only ever fires if the text was somehow set without
    // ever tapping the picker.
    if (dispatcherLat == null || dispatcherLng == null) {
      return err(
        dispatcherAddressFocus,
        'Select the package collection address on the map to calculate the delivery fee.',
      );
    }

    // Package weight — required for Hoppr Dispatcher (the HTP Delivery Fee's
    // weight charge can't be calculated without it; see
    // DeliveryFeeEstimator/backend deliveryFee.service.ts). Optional in
    // firstInvalid() above since self-delivery never needs it.
    if (DeliveryFeeEstimator.parseWeightKg(weight.text) == null) {
      return err(
        weightFocus,
        'Enter a valid package weight (e.g. "1.5 kg") to calculate the delivery fee.',
      );
    }

    if (specialInstructions.text.trim().length > 500) {
      return err(
        specialInstructionsFocus,
        'Notes must be 500 characters or fewer.',
      );
    }

    return null;
  }

  Consignment toModel() => Consignment(
    product: product.text.trim(),
    amount: amount.text.trim(),
    quantity: quantity.text.trim(),
    weight: _weightWithUnit,
    buyerName: buyerName.text.trim(),
    buyerContact: buyerContact.text.trim(),
    deliveryAddress: deliveryAddress.text.trim(),
    deliveryLat: deliveryLat,
    deliveryLng: deliveryLng,
    estimatedDeliveryDate: estimatedDeliveryDate.text.trim(),
    estimatedDeliveryTime: estimatedDeliveryTime.text.trim(),
    waybillTrackingNumber: waybillTrackingNumber.text.trim(),
    dispatcherName: dispatcherName.text.trim(),
    dispatcherPhone: dispatcherPhone.text.trim(),
    dispatcherAddress: dispatcherAddress.text.trim(),
    dispatcherLat: dispatcherLat,
    dispatcherLng: dispatcherLng,
    specialInstructions: specialInstructions.text.trim(),
    hasDispatchPhoto: hasDispatchPhoto,
    hasWaybillImage: hasWaybill,
    productPhotoUrl: productPhotoUrl,
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
      estimatedDeliveryDate,
      estimatedDeliveryTime,
      waybillTrackingNumber,
      dispatcherName,
      dispatcherPhone,
      dispatcherAddress,
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
      estimatedDeliveryDateFocus,
      estimatedDeliveryTimeFocus,
      waybillTrackingFocus,
      dispatcherNameFocus,
      dispatcherPhoneFocus,
      dispatcherAddressFocus,
      specialInstructionsFocus,
    ]) {
      node.dispose();
    }
  }
}
