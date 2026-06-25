import '../../core/network/json.dart';

/// A saved bank account the user receives settlements / withdrawals into.
class PayoutAccount {
  const PayoutAccount({
    required this.id,
    required this.bank,
    required this.accountNumberLast4,
    required this.accountName,
    required this.isDefault,
    required this.verified,
  });

  final String id;
  final String bank;
  final String accountNumberLast4;
  final String accountName;
  final bool isDefault;
  final bool verified;

  factory PayoutAccount.fromJson(Map<String, dynamic> j) => PayoutAccount(
        id: asId(j['id'] ?? j['_id']),
        bank: asString(j['bank']),
        accountNumberLast4: asString(j['accountNumberLast4']),
        accountName: asString(j['accountName']),
        isDefault: asBool(j['isDefault']),
        verified: asBool(j['verified']),
      );
}

/// Date of birth captured as discrete parts (mirrors the Edit Profile UI).
class ProfileDob {
  const ProfileDob({required this.day, required this.month, required this.year});

  final int day;
  final int month;
  final int year;

  static ProfileDob? fromJson(Map<String, dynamic> j) {
    if (j.isEmpty) return null;
    final day = asInt(j['day']);
    final month = asInt(j['month']);
    final year = asInt(j['year']);
    if (day == 0 && month == 0 && year == 0) return null;
    return ProfileDob(day: day, month: month, year: year);
  }

  Map<String, dynamic> toJson() => {'day': day, 'month': month, 'year': year};
}

/// Postal address captured on the Edit Profile screen.
class ProfileAddress {
  const ProfileAddress({
    this.line1,
    this.line2,
    this.city,
    this.state,
    this.postalCode,
    this.country,
  });

  final String? line1;
  final String? line2;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;

  static ProfileAddress? fromJson(Map<String, dynamic> j) {
    if (j.isEmpty) return null;
    return ProfileAddress(
      line1: asStringOrNull(j['line1']),
      line2: asStringOrNull(j['line2']),
      city: asStringOrNull(j['city']),
      state: asStringOrNull(j['state']),
      postalCode: asStringOrNull(j['postalCode']),
      country: asStringOrNull(j['country']),
    );
  }
}

/// The authenticated user. Money stays in **kobo** (integers) to match the
/// server exactly — divide by 100 only at display time.
class ApiUser {
  const ApiUser({
    required this.id,
    required this.fullName,
    required this.phone,
    this.email,
    this.accountType = 'individual',
    this.firstName,
    this.middleName,
    this.lastName,
    this.dob,
    this.phoneCountry,
    this.address,
    required this.trustScore,
    required this.trustGrade,
    required this.deals,
    required this.disputes,
    required this.verified,
    required this.identityStatus,
    required this.escrowBalanceKobo,
    required this.walletAvailableKobo,
    required this.walletCoolingKobo,
    this.payoutAccounts = const [],
  });

  final String id;
  final String fullName;
  final String phone;
  final String? email;

  // ── Extended profile (Edit Profile screen) ─────────────────────────────────
  final String accountType; // individual | company
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final ProfileDob? dob;
  final String? phoneCountry; // ISO-3166 alpha-2
  final ProfileAddress? address;

  final int trustScore; // 0..100
  final String trustGrade; // "A+", "A", ...
  final int deals;
  final int disputes;
  final bool verified;
  final String identityStatus; // unverified | pending | verified | rejected

  final int escrowBalanceKobo; // locked in active escrows
  final int walletAvailableKobo; // withdrawable
  final int walletCoolingKobo; // pending cooling release

  /// Saved bank accounts for settlements / withdrawals.
  final List<PayoutAccount> payoutAccounts;

  /// The default payout account (or the first, or null when none are saved).
  PayoutAccount? get defaultPayoutAccount {
    if (payoutAccounts.isEmpty) return null;
    return payoutAccounts.firstWhere((a) => a.isDefault,
        orElse: () => payoutAccounts.first);
  }

  /// First name for greetings — the structured field if set, else derived.
  String get displayFirstName =>
      (firstName?.trim().isNotEmpty ?? false)
          ? firstName!.trim()
          : fullName.trim().split(RegExp(r'\s+')).first;

  factory ApiUser.fromJson(Map<String, dynamic> j) => ApiUser(
        id: asId(j['id'] ?? j['_id']),
        fullName: asString(j['fullName']),
        phone: asString(j['phone']),
        email: asStringOrNull(j['email']),
        accountType: asString(j['accountType'], 'individual'),
        firstName: asStringOrNull(j['firstName']),
        middleName: asStringOrNull(j['middleName']),
        lastName: asStringOrNull(j['lastName']),
        dob: ProfileDob.fromJson(asMap(j['dob'])),
        phoneCountry: asStringOrNull(j['phoneCountry']),
        address: ProfileAddress.fromJson(asMap(j['address'])),
        trustScore: asInt(j['trustScore'], 80),
        trustGrade: asString(j['trustGrade'], 'A'),
        deals: asInt(j['deals']),
        disputes: asInt(j['disputes']),
        verified: asBool(j['verified']),
        identityStatus: asString(asMap(j['identity'])['status'], 'unverified'),
        escrowBalanceKobo: asInt(j['escrowBalanceKobo']),
        walletAvailableKobo: asInt(j['walletAvailableKobo']),
        walletCoolingKobo: asInt(j['walletCoolingKobo']),
        payoutAccounts: asList(j['payoutAccounts'])
            .map((e) => PayoutAccount.fromJson(asMap(e)))
            .toList(growable: false),
      );
}
