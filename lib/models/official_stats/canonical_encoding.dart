import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import 'contract_versions.dart';

/// Deterministic canonical JSON used for hashes, idempotency keys, and fencing.
///
/// Contract v1 permits null, booleans, strings, mathematical safe integers,
/// UTC timestamps, lists, and maps with ASCII schema keys. Integer-valued Dart
/// doubles are normalized to integers because JSON does not retain whether a
/// number was written as `1`, `1.0`, or `1e0`; negative zero likewise
/// canonicalizes to `0`. Fractional and non-finite numbers and unordered
/// collections are rejected. Map keys are sorted by ASCII code point. Text is
/// normalized to Unicode NFC and timestamps to UTC millisecond precision.
abstract final class OfficialStatCanonicalEncoding {
  static const int maxSafeInteger = 9007199254740991;
  static final RegExp _asciiKey = RegExp(r'^[\x21-\x7E]+$');

  static String encode(Object? value) => jsonEncode(_normalize(value));

  static String sha256Hex(Object? value) =>
      sha256.convert(utf8.encode(encode(value))).toString();

  static Map<String, Object?> envelope(Object? value) => {
    'encodingVersion': OfficialStatContractVersions.canonicalEncoding,
    'value': value,
  };

  static Object? _normalize(Object? value) {
    if (value == null || value is bool) return value;
    if (value is String) return unicode.nfc(value);
    if (value is int) {
      if (value < -maxSafeInteger || value > maxSafeInteger) {
        throw FormatException(
          'Integer is outside the cross-runtime safe range',
        );
      }
      return value;
    }
    if (value is double) {
      if (!value.isFinite) {
        throw FormatException('Canonical numbers must be finite safe integers');
      }
      if (value < -maxSafeInteger ||
          value > maxSafeInteger ||
          value.truncateToDouble() != value) {
        throw FormatException('Canonical numbers must be safe integers');
      }
      return value.toInt();
    }
    if (value is num) {
      throw FormatException('Unsupported numeric value: ${value.runtimeType}');
    }
    if (value is DateTime) return normalizeTimestamp(value);
    if (value is List<Object?>) return value.map(_normalize).toList();
    if (value is Set<Object?>) {
      throw FormatException('Unordered sets are not canonical');
    }
    if (value is Map) {
      final entries = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String || !_asciiKey.hasMatch(key)) {
          throw FormatException('Canonical map keys must be nonempty ASCII');
        }
        entries[key] = entry.value;
      }
      final keys = entries.keys.toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _normalize(entries[key]),
      };
    }
    throw FormatException('Unsupported canonical value: ${value.runtimeType}');
  }

  static String normalizeTimestamp(DateTime value) {
    final utc = value.toUtc();
    if (utc.year < 1 || utc.year > 9999) {
      throw FormatException('Canonical timestamps require years 0001-9999');
    }
    final milliseconds = utc.millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(
      milliseconds,
      isUtc: true,
    ).toIso8601String();
  }
}

/// IDs are opaque and never derived from a name, jersey, email, or likeness.
abstract final class OfficialStatIdentifiers {
  static final RegExp _id = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
  static final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

  static bool isValid(String value) => _id.hasMatch(value);

  static bool isSha256(String value) => _sha256.hasMatch(value);

  static void requireValid(String field, String value) {
    if (!isValid(value)) {
      throw FormatException('$field must be an opaque 1-128 character ID');
    }
  }

  static void requireSha256(String field, String value) {
    if (!isSha256(value)) {
      throw FormatException('$field must be lowercase SHA-256 hex');
    }
  }
}
