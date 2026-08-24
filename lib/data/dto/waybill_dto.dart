import '../../core/network/json.dart';

/// The structured, generated Hoppr Waybill for one consignment — mirrors
/// backend `WaybillSub` (transaction.model.ts). One common shape for all
/// three input pipelines: `method` says which one produced it —
/// 'hoppr_logistics' (from the transaction, no scan), 'external_logistics'
/// (an external document was scanned), or 'external_manual' (External
/// Delivery with no document — entered by hand, no scan attempted).
class WaybillDto {
  const WaybillDto({
    required this.status,
    required this.method,
    this.waybillNumber,
    this.shipperName,
    this.shipperPhone,
    this.shipperAddress,
    this.consigneeName,
    this.consigneePhone,
    this.consigneeAddress,
    this.itemDescription,
    this.quantity,
    this.packageType,
    this.weightKg,
    this.declaredValueKobo,
    this.pickupLocation,
    this.deliveryLocation,
    this.specialInstructions,
    this.merchantBusinessName,
    this.merchantContactPerson,
    this.merchantPhone,
    this.merchantAddress,
    this.sourceDocumentUrl,
    this.pdfUrl,
    this.scanWarnings = const [],
  });

  factory WaybillDto.fromJson(Map<String, dynamic> json) => WaybillDto(
        status: asString(json['status'], 'draft'),
        method: asString(json['method'], 'hoppr_logistics'),
        waybillNumber: asStringOrNull(json['waybillNumber']),
        shipperName: asStringOrNull(json['shipperName']),
        shipperPhone: asStringOrNull(json['shipperPhone']),
        shipperAddress: asStringOrNull(json['shipperAddress']),
        consigneeName: asStringOrNull(json['consigneeName']),
        consigneePhone: asStringOrNull(json['consigneePhone']),
        consigneeAddress: asStringOrNull(json['consigneeAddress']),
        itemDescription: asStringOrNull(json['itemDescription']),
        quantity: asStringOrNull(json['quantity']),
        packageType: asStringOrNull(json['packageType']),
        weightKg: json['weightKg'] == null ? null : asDouble(json['weightKg']),
        declaredValueKobo: json['declaredValueKobo'] == null ? null : asInt(json['declaredValueKobo']),
        pickupLocation: asStringOrNull(json['pickupLocation']),
        deliveryLocation: asStringOrNull(json['deliveryLocation']),
        specialInstructions: asStringOrNull(json['specialInstructions']),
        merchantBusinessName: asStringOrNull(json['merchantBusinessName']),
        merchantContactPerson: asStringOrNull(json['merchantContactPerson']),
        merchantPhone: asStringOrNull(json['merchantPhone']),
        merchantAddress: asStringOrNull(json['merchantAddress']),
        sourceDocumentUrl: asStringOrNull(json['sourceDocumentUrl']),
        pdfUrl: asStringOrNull(json['pdfUrl']),
        scanWarnings: (json['scanWarnings'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );

  final String status; // 'draft' | 'confirmed'
  final String method; // 'hoppr_logistics' | 'external_logistics' | 'external_manual'
  final String? waybillNumber;
  final String? shipperName;
  final String? shipperPhone;
  final String? shipperAddress;
  final String? consigneeName;
  final String? consigneePhone;
  final String? consigneeAddress;
  final String? itemDescription;
  final String? quantity;
  final String? packageType;
  final double? weightKg;
  final int? declaredValueKobo;
  final String? pickupLocation;
  final String? deliveryLocation;
  final String? specialInstructions;
  final String? merchantBusinessName;
  final String? merchantContactPerson;
  final String? merchantPhone;
  final String? merchantAddress;
  final String? sourceDocumentUrl;
  final String? pdfUrl;
  /// Present only right after initExternalWaybill — non-persisted, one-shot
  /// feedback from the scan step (e.g. "couldn't read this clearly") for the
  /// review sheet to surface. Never populated on a plain GET.
  final List<String> scanWarnings;

  bool get isConfirmed => status == 'confirmed';
  bool get isHopprLogistics => method == 'hoppr_logistics';
  bool get isExternalManual => method == 'external_manual';
}
