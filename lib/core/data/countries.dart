/// A country for the address + phone-country dropdowns.
class Country {
  const Country(this.iso2, this.name, this.dialCode);
  final String iso2; // ISO-3166 alpha-2
  final String name;
  final String dialCode; // e.g. "+234"

  /// Unicode flag emoji derived from the ISO-2 code (e.g. NG → 🇳🇬).
  String get flag => String.fromCharCodes([
        iso2.codeUnitAt(0) - 0x41 + 0x1F1E6,
        iso2.codeUnitAt(1) - 0x41 + 0x1F1E6,
      ]);
}

/// The app's home country — pre-selected by default.
const String kDefaultCountryIso2 = 'NG';

Country? countryByIso2(String? iso2) {
  if (iso2 == null) return null;
  for (final c in kCountries) {
    if (c.iso2 == iso2) return c;
  }
  return null;
}

Country? countryByName(String? name) {
  if (name == null) return null;
  for (final c in kCountries) {
    if (c.name == name) return c;
  }
  return null;
}

/// A curated list covering the app's main markets plus common countries.
/// Extend freely — the dropdowns render whatever is here.
const List<Country> kCountries = [
  Country('NG', 'Nigeria', '+234'),
  Country('GH', 'Ghana', '+233'),
  Country('KE', 'Kenya', '+254'),
  Country('ZA', 'South Africa', '+27'),
  Country('EG', 'Egypt', '+20'),
  Country('TZ', 'Tanzania', '+255'),
  Country('UG', 'Uganda', '+256'),
  Country('RW', 'Rwanda', '+250'),
  Country('CI', "Côte d'Ivoire", '+225'),
  Country('SN', 'Senegal', '+221'),
  Country('CM', 'Cameroon', '+237'),
  Country('IN', 'India', '+91'),
  Country('PK', 'Pakistan', '+92'),
  Country('BD', 'Bangladesh', '+880'),
  Country('US', 'United States', '+1'),
  Country('CA', 'Canada', '+1'),
  Country('GB', 'United Kingdom', '+44'),
  Country('IE', 'Ireland', '+353'),
  Country('AU', 'Australia', '+61'),
  Country('NZ', 'New Zealand', '+64'),
  Country('DE', 'Germany', '+49'),
  Country('FR', 'France', '+33'),
  Country('IT', 'Italy', '+39'),
  Country('ES', 'Spain', '+34'),
  Country('PT', 'Portugal', '+351'),
  Country('NL', 'Netherlands', '+31'),
  Country('BE', 'Belgium', '+32'),
  Country('SE', 'Sweden', '+46'),
  Country('NO', 'Norway', '+47'),
  Country('DK', 'Denmark', '+45'),
  Country('CH', 'Switzerland', '+41'),
  Country('AE', 'United Arab Emirates', '+971'),
  Country('SA', 'Saudi Arabia', '+966'),
  Country('QA', 'Qatar', '+974'),
  Country('TR', 'Türkiye', '+90'),
  Country('CN', 'China', '+86'),
  Country('JP', 'Japan', '+81'),
  Country('KR', 'South Korea', '+82'),
  Country('SG', 'Singapore', '+65'),
  Country('MY', 'Malaysia', '+60'),
  Country('ID', 'Indonesia', '+62'),
  Country('PH', 'Philippines', '+63'),
  Country('BR', 'Brazil', '+55'),
  Country('MX', 'Mexico', '+52'),
  Country('AR', 'Argentina', '+54'),
];
