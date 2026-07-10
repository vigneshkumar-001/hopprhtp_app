import '../../core/network/json.dart';

/// Hoppr Vision's best-effort extraction from a scanned waybill/parcel photo
/// — every field is nullable and never fabricated. A null field means "not
/// detected" (or extraction isn't available yet — see [warnings]), never a
/// guessed value; the review screen shows exactly that distinction.
class ScanFields {
  const ScanFields({
    this.buyerName,
    this.buyerPhone,
    this.dispatcherPhone,
    this.itemName,
    this.itemDescription,
    this.amount,
    this.estimatedDelivery,
    this.pickupAddress,
    this.deliveryAddress,
    this.packageNotes,
  });

  final String? buyerName;
  final String? buyerPhone;
  final String? dispatcherPhone;
  final String? itemName;
  final String? itemDescription;
  final double? amount;
  final String? estimatedDelivery;
  final String? pickupAddress;
  final String? deliveryAddress;
  final String? packageNotes;

  bool get isEmpty =>
      buyerName == null &&
      buyerPhone == null &&
      dispatcherPhone == null &&
      itemName == null &&
      itemDescription == null &&
      amount == null &&
      estimatedDelivery == null &&
      pickupAddress == null &&
      deliveryAddress == null &&
      packageNotes == null;

  /// Ordered (label, value) pairs for the review screen — a null value
  /// renders as "Not detected", never a placeholder/sample string.
  List<(String label, String? value)> get displayFields => [
    ('Buyer name', buyerName),
    ('Buyer phone', buyerPhone),
    ('Dispatcher phone', dispatcherPhone),
    ('Item name', itemName),
    ('Item description', itemDescription),
    ('Amount', amount?.toStringAsFixed(2)),
    ('Estimated delivery', estimatedDelivery),
    // Displayed as "Package Collection Address" — never "Dispatcher Address"
    // (reads like the dispatcher's own address) or "Pickup Address" (not a
    // concept this app uses). The underlying field/wire name is unchanged
    // since it's an internal identifier shared with the backend scan
    // endpoint, out of scope here — only the on-screen label is corrected.
    ('Package Collection Address', pickupAddress),
    ('Delivery address', deliveryAddress),
    ('Package notes', packageNotes),
  ];

  factory ScanFields.fromJson(Map<String, dynamic> j) => ScanFields(
    buyerName: asStringOrNull(j['buyerName']),
    buyerPhone: asStringOrNull(j['buyerPhone']),
    dispatcherPhone: asStringOrNull(j['dispatcherPhone']),
    itemName: asStringOrNull(j['itemName']),
    itemDescription: asStringOrNull(j['itemDescription']),
    amount: j['amount'] == null ? null : asDouble(j['amount']),
    estimatedDelivery: asStringOrNull(j['estimatedDelivery']),
    pickupAddress: asStringOrNull(j['pickupAddress']),
    deliveryAddress: asStringOrNull(j['deliveryAddress']),
    packageNotes: asStringOrNull(j['packageNotes']),
  );
}

/// Response from `POST /transactions/scan`. [warnings] is shown verbatim as
/// a friendly banner — e.g. today it always explains that automatic
/// extraction isn't wired up yet, so the user knows to fill fields manually
/// rather than assuming a blank field means the photo was unreadable.
class ScanResult {
  const ScanResult({
    required this.imageUrl,
    required this.fields,
    required this.warnings,
  });

  final String imageUrl;
  final ScanFields fields;
  final List<String> warnings;

  factory ScanResult.fromJson(Map<String, dynamic> j) => ScanResult(
    imageUrl: asString(j['imageUrl']),
    fields: ScanFields.fromJson(asMap(j['fields'])),
    warnings: asList(
      j['warnings'],
    ).map((e) => e.toString()).toList(growable: false),
  );
}
