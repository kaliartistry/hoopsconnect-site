import '../../models/official_stats/canonical_encoding.dart';
import 'journal_error.dart';
import 'journal_limits.dart';
import 'journal_validation.dart';

final class LocalKeyValue {
  final String key;
  final String value;

  const LocalKeyValue(this.key, this.value);
}

/// Returns the first UTF-16 key strictly after every key beginning with
/// [prefix]. Journal prefixes are nonempty ASCII paths, so this successor is
/// ordered identically by SQLite's binary collation and IndexedDB.
String localJournalPrefixExclusiveUpperBound(String prefix) {
  if (prefix.isEmpty) {
    throw ArgumentError.value(prefix, 'prefix', 'must not be empty');
  }
  final codeUnits = prefix.codeUnits.toList(growable: false);
  for (var index = codeUnits.length - 1; index >= 0; index--) {
    if (codeUnits[index] < 0xffff) {
      return String.fromCharCodes([
        ...codeUnits.take(index),
        codeUnits[index] + 1,
      ]);
    }
  }
  throw ArgumentError.value(prefix, 'prefix', 'has no finite upper bound');
}

abstract interface class LocalJournalStoreTransaction {
  Future<String?> get(String key);

  Future<void> put(String key, String value);

  Future<void> delete(String key);

  /// Returns keys in ascending binary/Unicode order after [startAfter].
  Future<List<LocalKeyValue>> scanPrefix(
    String prefix, {
    String? startAfter,
    required int limit,
  });
}

abstract interface class LocalGameJournalStore {
  Future<LocalStorageCapability> open();

  LocalStorageCapability get capability;

  Future<T> transaction<T>(
    Future<T> Function(LocalJournalStoreTransaction transaction) action,
  );

  Future<void> close();
}

/// Every stored value has an own canonical checksum. Operation hash-chain
/// verification remains separate and is performed by the repository.
abstract final class LocalJournalRecordCodec {
  static String encode(Map<String, Object?> payload) => encodeVersioned(
    payload,
    localSchemaVersion: LocalGameJournalLimits.localSchemaVersion,
  );

  /// Writes an envelope for a specific logical schema version.
  ///
  /// Active records always use [encode]. Migration metadata is the only
  /// caller that may need to persist an older marker while a reviewed upgrade
  /// is in progress.
  static String encodeVersioned(
    Map<String, Object?> payload, {
    required int localSchemaVersion,
  }) {
    LocalJournalValidation.requireSafeInteger(
      'localSchemaVersion',
      localSchemaVersion,
      minimum: 1,
    );
    final checksum = OfficialStatCanonicalEncoding.sha256Hex(payload);
    return OfficialStatCanonicalEncoding.encode({
      'checksum': checksum,
      'localSchemaVersion': localSchemaVersion,
      'payload': payload,
    });
  }

  static Map<String, Object?> decode(String encoded) {
    final decoded = decodeVersioned(encoded);
    if (decoded.localSchemaVersion !=
        LocalGameJournalLimits.localSchemaVersion) {
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedSchemaVersion,
        'Stored local journal schema is unsupported',
        {'localSchemaVersion': decoded.localSchemaVersion},
      );
    }
    return decoded.payload;
  }

  /// Decodes and verifies a record without treating an older schema as
  /// current. Only the migration runner should use this entry point.
  static LocalJournalDecodedRecord decodeVersioned(String encoded) {
    try {
      final envelope = LocalJournalValidation.decodeMap(encoded);
      LocalJournalValidation.exactKeys(envelope, const {
        'checksum',
        'localSchemaVersion',
        'payload',
      });
      final version = LocalJournalValidation.requireSafeInteger(
        'localSchemaVersion',
        envelope['localSchemaVersion'],
        minimum: 1,
      );
      final rawPayload = envelope['payload'];
      if (rawPayload is! Map) {
        throw LocalJournalException(
          LocalJournalErrorCode.mutatedRecord,
          'Stored journal payload is not an object',
        );
      }
      final payload = Map<String, Object?>.from(rawPayload);
      final expected = LocalJournalValidation.requireHash(
        'checksum',
        envelope['checksum'],
      );
      final actual = OfficialStatCanonicalEncoding.sha256Hex(payload);
      if (expected != actual) {
        throw LocalJournalException(
          LocalJournalErrorCode.mutatedRecord,
          'Stored journal record checksum mismatch',
        );
      }
      return LocalJournalDecodedRecord(
        localSchemaVersion: version,
        payload: payload,
      );
    } on LocalJournalException catch (error) {
      if (error.code == LocalJournalErrorCode.mutatedRecord) rethrow;
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Stored journal record envelope is malformed',
      );
    } on FormatException {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Stored journal record payload is not canonical',
      );
    }
  }
}

final class LocalJournalDecodedRecord {
  final int localSchemaVersion;
  final Map<String, Object?> payload;

  const LocalJournalDecodedRecord({
    required this.localSchemaVersion,
    required this.payload,
  });
}
