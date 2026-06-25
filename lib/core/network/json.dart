// Small, defensive JSON coercion helpers used by the DTO `fromJson` factories.
// They tolerate the loose shapes a JSON API can return (numbers as strings,
// missing keys, Mongo `_id` objects) so parsing never throws on a stray field.

String asString(dynamic v, [String fallback = '']) => v?.toString() ?? fallback;

String? asStringOrNull(dynamic v) => v?.toString();

int asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double asDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

bool asBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is String) return v == 'true';
  return fallback;
}

/// Parses an ISO-8601 timestamp to local time; null if absent/invalid.
DateTime? asDateTime(dynamic v) {
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  return null;
}

Map<String, dynamic> asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<dynamic> asList(dynamic v) => v is List ? v : const [];

/// Extracts an id whether the server sent the `id` virtual (detail responses)
/// or a raw Mongo `_id` (lean list responses, which may serialise as a string
/// or an `{ $oid: ... }` object).
String asId(dynamic v) {
  if (v is String) return v;
  if (v is Map) return (v[r'$oid'] ?? v['_id'] ?? '').toString();
  return v?.toString() ?? '';
}
