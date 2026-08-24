import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/dto/waybill_dto.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/feedback/app_snackbar.dart';

/// Seller-only "Hoppr Waybill" card + review sheet.
///
/// Three input pipelines feed one common review/confirm flow (see
/// backend waybill.service.ts for the full business rules this mirrors),
/// all ending in exactly the same standardized Hoppr Waybill:
///  - `seller_self_delivery` / `request_hoppr_dispatcher` (Deliver Myself /
///    Hoppr Dispatcher): fields are auto-filled from the transaction itself
///    the moment the seller opens the sheet — no scan/AI call is ever made.
///  - `external_logistics` (External Delivery — an outside courier like
///    GIG/DHL/UPS, or an independent third-party rider): the seller is
///    first asked whether they already have a Waybill/shipping document.
///    YES uploads it and the backend runs a real AI scan, pre-filling the
///    review form (anything it wasn't confident about is left blank with a
///    warning, never guessed). NO skips scanning entirely — there is
///    nothing to scan — and the seller fills every field in by hand.
/// No path ever calls itself "done" until the seller explicitly confirms —
/// that's the one moment the PDF is generated, and mandatory fields must all
/// be filled before Confirm becomes tappable.
class WaybillSection extends ConsumerStatefulWidget {
  const WaybillSection({
    super.key,
    required this.transactionId,
    required this.dispatcherMode,
    required this.isSeller,
    this.consignmentIndex = 0,
  });

  final String transactionId;
  final String dispatcherMode; // 'seller_self_delivery' | 'request_hoppr_dispatcher'
  final bool isSeller;
  final int consignmentIndex;

  @override
  ConsumerState<WaybillSection> createState() => _WaybillSectionState();
}

class _WaybillSectionState extends ConsumerState<WaybillSection> {
  WaybillDto? _waybill;
  bool _loading = true;

  /// Only an external-courier delivery has a document to scan. Both
  /// "Deliver Myself" and "Hoppr Dispatcher" already have every field in our
  /// own data, so their waybill is generated directly and never costs a scan
  /// (the backend enforces this too — see waybill.service.ts).
  bool get _isHopprLogistics => widget.dispatcherMode != 'external_logistics';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final wb = await ref
          .read(transactionRepositoryProvider)
          .getWaybill(widget.transactionId, widget.consignmentIndex);
      if (!mounted) return;
      setState(() {
        _waybill = wb;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startHopprFlow() async {
    try {
      final wb = await ref
          .read(transactionRepositoryProvider)
          .initHopprWaybill(widget.transactionId, widget.consignmentIndex);
      if (!mounted) return;
      setState(() => _waybill = wb);
      _openReviewSheet();
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  /// Entry point for External Delivery — asks whether the seller already
  /// has a Waybill/shipping document before doing anything else, exactly
  /// the branch point the business rule requires: a scan is only ever
  /// attempted when there is a real document to read.
  Future<void> _startExternalFlow() async {
    final hasDocument = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.xl),
      builder: (_) => const _HasDocumentSheet(),
    );
    if (hasDocument == null || !mounted) return;
    if (hasDocument) {
      await _startExternalScanFlow();
    } else {
      await _startExternalManualFlow();
    }
  }

  /// YES branch — seller has a real document: upload it, then the backend
  /// runs a real AI scan against it (see initExternalWaybill's sourceDocumentUrl).
  Future<void> _startExternalScanFlow() async {
    final picked = await showModalBottomSheet<XFile?>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.xl),
      builder: (_) => _ImageSourceSheet(),
    );
    if (picked == null || !mounted) return;
    try {
      final url = await ref.read(uploadRepositoryProvider).uploadImage(picked.path);
      final wb = await ref.read(transactionRepositoryProvider).initExternalWaybill(
            widget.transactionId,
            widget.consignmentIndex,
            sourceDocumentUrl: url,
          );
      if (!mounted) return;
      setState(() => _waybill = wb);
      _openReviewSheet();
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  /// NO branch — no document exists to scan (e.g. an independent dispatch
  /// rider who issues nothing formal). No upload, no scan call at all — the
  /// seller goes straight to filling in delivery details by hand.
  Future<void> _startExternalManualFlow() async {
    try {
      final wb = await ref
          .read(transactionRepositoryProvider)
          .initExternalWaybill(widget.transactionId, widget.consignmentIndex);
      if (!mounted) return;
      setState(() => _waybill = wb);
      _openReviewSheet();
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  void _openReviewSheet() {
    if (_waybill == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.xl),
      builder: (_) => _WaybillReviewSheet(
        transactionId: widget.transactionId,
        consignmentIndex: widget.consignmentIndex,
        waybill: _waybill!,
        onConfirmed: (wb) {
          if (mounted) setState(() => _waybill = wb);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final wb = _waybill;

    // Buyers get a read-only view — nothing to see (or manage) until the
    // seller/dispatcher has actually confirmed a final waybill.
    if (!widget.isSeller) {
      if (wb == null || !wb.isConfirmed) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.all(AppSizes.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.lg,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_rounded, size: 18),
                const SizedBox(width: AppSizes.sm),
                Text('Hoppr Waybill', style: AppText.h3),
              ],
            ),
            const SizedBox(height: AppSizes.sm),
            Text(wb.waybillNumber ?? '', style: AppText.bodyStrong),
            const SizedBox(height: AppSizes.md),
            AppButton(
              label: 'View Waybill (PDF)',
              icon: Icons.picture_as_pdf_rounded,
              variant: AppButtonVariant.outline,
              onPressed: wb.pdfUrl == null
                  ? null
                  : () => launchUrl(Uri.parse(wb.pdfUrl!), mode: LaunchMode.externalApplication),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.lg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, size: 18),
              const SizedBox(width: AppSizes.sm),
              Text('Hoppr Waybill', style: AppText.h3),
              const Spacer(),
              if (wb != null) _StatusPill(status: wb.status),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          if (wb == null) ...[
            Text(
              _isHopprLogistics
                  ? 'Generate a waybill from this transaction\'s existing details.'
                  : 'Whether it\'s a courier or an independent rider, generate a Hoppr Waybill for this delivery.',
              style: AppText.body,
            ),
            const SizedBox(height: AppSizes.md),
            AppButton(
              label: _isHopprLogistics ? 'Generate Waybill' : 'Start External Delivery Waybill',
              icon: _isHopprLogistics ? Icons.auto_awesome_rounded : Icons.local_shipping_outlined,
              onPressed: _isHopprLogistics ? _startHopprFlow : _startExternalFlow,
            ),
          ] else if (!wb.isConfirmed) ...[
            Text('Review and confirm the details to generate the final waybill.', style: AppText.body),
            const SizedBox(height: AppSizes.md),
            AppButton(label: 'Continue review', onPressed: _openReviewSheet),
          ] else ...[
            Text(wb.waybillNumber ?? '', style: AppText.bodyStrong),
            const SizedBox(height: AppSizes.md),
            AppButton(
              label: 'View Waybill (PDF)',
              icon: Icons.picture_as_pdf_rounded,
              variant: AppButtonVariant.outline,
              onPressed: wb.pdfUrl == null
                  ? null
                  : () => launchUrl(Uri.parse(wb.pdfUrl!), mode: LaunchMode.externalApplication),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final confirmed = status == 'confirmed';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 2),
      decoration: BoxDecoration(
        color: (confirmed ? Colors.green : Colors.orange).withValues(alpha: 0.12),
        borderRadius: AppRadii.pill,
      ),
      child: Text(
        confirmed ? 'Confirmed' : 'Draft',
        style: AppText.caption.copyWith(color: confirmed ? Colors.green[800] : Colors.orange[800]),
      ),
    );
  }
}

/// The branch point for External Delivery — asked before anything else so a
/// scan is only ever attempted when a real document exists to read.
class _HasDocumentSheet extends StatelessWidget {
  const _HasDocumentSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Do you already have a Waybill or shipping document', style: AppText.h3),
            Text('from the delivery provider?', style: AppText.h3),
            const SizedBox(height: AppSizes.xs),
            Text(
              'This could be a courier\'s printed waybill, or nothing at all if you\'re using an independent rider.',
              style: AppText.body,
            ),
            const SizedBox(height: AppSizes.lg),
            AppButton(
              label: 'Yes, I have one',
              icon: Icons.upload_file_rounded,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: AppSizes.sm),
            AppButton(
              label: 'No, enter details manually',
              icon: Icons.edit_outlined,
              variant: AppButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageSourceSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add external waybill', style: AppText.h3),
            const SizedBox(height: AppSizes.md),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () async {
                final f = await ImagePicker().pickImage(
                  source: ImageSource.camera, imageQuality: 85, maxWidth: 1800,
                );
                if (context.mounted) Navigator.of(context).pop(f);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Upload from gallery'),
              onTap: () async {
                final f = await ImagePicker().pickImage(
                  source: ImageSource.gallery, imageQuality: 85, maxWidth: 1800,
                );
                if (context.mounted) Navigator.of(context).pop(f);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One common review UI for both flows — the fields shown are identical
/// either way (business rule: "same standardized Hoppr Waybill format").
/// hoppr_logistics arrives mostly pre-filled; external_logistics arrives
/// blank (until OCR is wired in) — either way every field stays editable
/// and nothing is final until "Confirm & Generate" is tapped.
class _WaybillReviewSheet extends ConsumerStatefulWidget {
  const _WaybillReviewSheet({
    required this.transactionId,
    required this.consignmentIndex,
    required this.waybill,
    required this.onConfirmed,
  });

  final String transactionId;
  final int consignmentIndex;
  final WaybillDto waybill;
  final void Function(WaybillDto) onConfirmed;

  @override
  ConsumerState<_WaybillReviewSheet> createState() => _WaybillReviewSheetState();
}

class _WaybillReviewSheetState extends ConsumerState<_WaybillReviewSheet> {
  late final TextEditingController _shipperName, _shipperPhone, _shipperAddress;
  late final TextEditingController _consigneeName, _consigneePhone, _consigneeAddress;
  late final TextEditingController _itemDescription, _quantity, _packageType;
  late final TextEditingController _pickupLocation, _deliveryLocation, _specialInstructions;
  bool _busy = false;

  /// Mirrors the backend's own required-field list (waybill.service.ts
  /// confirm()) — Confirm & Generate Waybill only becomes tappable once
  /// every one of these is filled, so a seller never taps it just to be
  /// bounced back by a server error for a field they could see was empty.
  List<TextEditingController> get _mandatoryControllers => [
    _shipperName, _shipperPhone,
    _consigneeName, _consigneePhone, _consigneeAddress,
    _itemDescription, _deliveryLocation,
  ];

  bool get _canConfirm => _mandatoryControllers.every((c) => c.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    final w = widget.waybill;
    _shipperName = TextEditingController(text: w.shipperName ?? '');
    _shipperPhone = TextEditingController(text: w.shipperPhone ?? '');
    _shipperAddress = TextEditingController(text: w.shipperAddress ?? '');
    _consigneeName = TextEditingController(text: w.consigneeName ?? '');
    _consigneePhone = TextEditingController(text: w.consigneePhone ?? '');
    _consigneeAddress = TextEditingController(text: w.consigneeAddress ?? '');
    _itemDescription = TextEditingController(text: w.itemDescription ?? '');
    _quantity = TextEditingController(text: w.quantity ?? '');
    _packageType = TextEditingController(text: w.packageType ?? '');
    _pickupLocation = TextEditingController(text: w.pickupLocation ?? '');
    _deliveryLocation = TextEditingController(text: w.deliveryLocation ?? '');
    _specialInstructions = TextEditingController(text: w.specialInstructions ?? '');
    for (final c in _mandatoryControllers) {
      c.addListener(_onMandatoryFieldChanged);
    }
  }

  void _onMandatoryFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [
      _shipperName, _shipperPhone, _shipperAddress,
      _consigneeName, _consigneePhone, _consigneeAddress,
      _itemDescription, _quantity, _packageType,
      _pickupLocation, _deliveryLocation, _specialInstructions,
    ]) {
      if (_mandatoryControllers.contains(c)) c.removeListener(_onMandatoryFieldChanged);
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveAndConfirm() async {
    setState(() => _busy = true);
    final repo = ref.read(transactionRepositoryProvider);
    try {
      await repo.updateWaybill(widget.transactionId, widget.consignmentIndex, {
        'shipperName': _shipperName.text.trim(),
        'shipperPhone': _shipperPhone.text.trim(),
        'shipperAddress': _shipperAddress.text.trim(),
        'consigneeName': _consigneeName.text.trim(),
        'consigneePhone': _consigneePhone.text.trim(),
        'consigneeAddress': _consigneeAddress.text.trim(),
        'itemDescription': _itemDescription.text.trim(),
        'quantity': _quantity.text.trim(),
        'packageType': _packageType.text.trim(),
        'pickupLocation': _pickupLocation.text.trim(),
        'deliveryLocation': _deliveryLocation.text.trim(),
        'specialInstructions': _specialInstructions.text.trim(),
      });
      final confirmed = await repo.confirmWaybill(widget.transactionId, widget.consignmentIndex);
      if (!mounted) return;
      widget.onConfirmed(confirmed);
      Navigator.of(context).pop();
      AppSnackbar.success(context, 'Waybill ${confirmed.waybillNumber ?? ''} generated.');
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
              AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.xxl),
          children: [
            Text('Review Waybill', style: AppText.h2),
            const SizedBox(height: AppSizes.xs),
            Text(
              widget.waybill.isHopprLogistics
                  ? 'Pre-filled from this transaction — check everything before confirming.'
                  : 'Fill in or correct the details below before confirming.',
              style: AppText.body,
            ),
            if (widget.waybill.scanWarnings.isNotEmpty) ...[
              const SizedBox(height: AppSizes.sm),
              Container(
                padding: const EdgeInsets.all(AppSizes.sm),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: AppRadii.md,
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: AppColors.warning),
                    const SizedBox(width: AppSizes.sm),
                    Expanded(
                      child: Text(
                        widget.waybill.scanWarnings.join(' '),
                        style: AppText.caption.copyWith(color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSizes.lg),
            Text('Shipper (From)', style: AppText.title),
            const SizedBox(height: AppSizes.sm),
            AppTextField(label: 'Name', required: true, controller: _shipperName),
            const SizedBox(height: AppSizes.sm),
            AppTextField(label: 'Phone', required: true, controller: _shipperPhone, keyboardType: TextInputType.phone),
            const SizedBox(height: AppSizes.sm),
            AppTextField(label: 'Address', controller: _shipperAddress),
            const SizedBox(height: AppSizes.lg),
            Text('Consignee (To)', style: AppText.title),
            const SizedBox(height: AppSizes.sm),
            AppTextField(label: 'Name', required: true, controller: _consigneeName),
            const SizedBox(height: AppSizes.sm),
            AppTextField(label: 'Phone', required: true, controller: _consigneePhone, keyboardType: TextInputType.phone),
            const SizedBox(height: AppSizes.sm),
            AppTextField(label: 'Address', required: true, controller: _consigneeAddress),
            const SizedBox(height: AppSizes.lg),
            Text('Shipment', style: AppText.title),
            const SizedBox(height: AppSizes.sm),
            AppTextField(label: 'Item description', required: true, controller: _itemDescription),
            const SizedBox(height: AppSizes.sm),
            Row(
              children: [
                Expanded(child: AppTextField(label: 'Quantity', controller: _quantity)),
                const SizedBox(width: AppSizes.sm),
                Expanded(child: AppTextField(label: 'Package type', controller: _packageType)),
              ],
            ),
            const SizedBox(height: AppSizes.lg),
            Text('Pickup & Delivery', style: AppText.title),
            const SizedBox(height: AppSizes.sm),
            AppTextField(label: 'Pickup location', controller: _pickupLocation),
            const SizedBox(height: AppSizes.sm),
            AppTextField(label: 'Delivery location', required: true, controller: _deliveryLocation),
            const SizedBox(height: AppSizes.sm),
            AppTextField(
              label: 'Special instructions (optional)',
              controller: _specialInstructions,
              maxLines: 3,
            ),
            const SizedBox(height: AppSizes.lg),
            if (!_canConfirm)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSizes.sm),
                child: Text(
                  'Fill in every required field (marked *) to continue.',
                  style: AppText.caption.copyWith(color: AppColors.warning),
                ),
              ),
            AppButton(
              label: 'Confirm & Generate Waybill',
              loading: _busy,
              enabled: _canConfirm,
              onPressed: _saveAndConfirm,
            ),
          ],
        ),
      ),
    );
  }
}
