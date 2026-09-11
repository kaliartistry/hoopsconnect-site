import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/firestore_paths.dart';
import '../../models/season_model.dart';

typedef SeasonCallable =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, Object?> data,
    );

class SeasonRepository {
  final FirebaseFirestore? _configuredFirestore;
  final FirebaseFunctions? _functions;
  final SeasonCallable? _callable;
  final SeasonOperationStore _operationStore;
  final Random _random;

  SeasonRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    SeasonCallable? callable,
    SeasonOperationStore? operationStore,
    Random? random,
  }) : _configuredFirestore = firestore,
       _functions = functions,
       _callable = callable,
       _operationStore =
           operationStore ?? SharedPreferencesSeasonOperationStore(),
       _random = random ?? Random.secure();

  FirebaseFirestore get _db =>
      _configuredFirestore ?? FirebaseFirestore.instance;

  CollectionReference<SeasonModel> _seasonsRef(String associationId) {
    return _db
        .collection(FirestorePaths.seasons(associationId))
        .withConverter<SeasonModel>(
          fromFirestore: SeasonModel.fromFirestore,
          toFirestore: (_, _) =>
              throw UnsupportedError('Season writes are callable-only.'),
        );
  }

  Stream<List<SeasonModel>> watchSeasons(String associationId) {
    return _seasonsRef(associationId).snapshots().map((snapshot) {
      final seasons = snapshot.docs.map((doc) => doc.data()).toList();
      seasons.sort((left, right) {
        final byStart = right.startDate.compareTo(left.startDate);
        return byStart != 0 ? byStart : left.name.compareTo(right.name);
      });
      return List.unmodifiable(seasons);
    });
  }

  static String stableSeasonId(String name) {
    return name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  static String dateOnly(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<SeasonOperationReceipt> prepareSeason({
    required String actorId,
    required String associationId,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final trimmedName = name.trim();
    final seasonId = stableSeasonId(trimmedName);
    if (trimmedName.isEmpty || seasonId.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Enter a season name.');
    }
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    if (start.isAfter(end)) {
      throw ArgumentError(
        'The season start date must be on or before its end date.',
      );
    }
    return _run(
      actorId: actorId,
      associationId: associationId,
      action: 'prepare',
      seasonId: seasonId,
      request: {
        'schemaVersion': 1,
        'seasonId': seasonId,
        'name': trimmedName,
        'startDate': dateOnly(start),
        'endDate': dateOnly(end),
      },
    );
  }

  Future<SeasonOperationReceipt> activateSeason({
    required String actorId,
    required String associationId,
    required SeasonModel season,
    required String currentSeasonId,
  }) {
    return _run(
      actorId: actorId,
      associationId: associationId,
      action: 'activate',
      seasonId: season.id,
      request: {
        'schemaVersion': 1,
        'seasonId': season.id,
        'expectedSeasonVersion': season.version,
        'expectedCurrentSeasonId': currentSeasonId,
      },
    );
  }

  Future<SeasonOperationReceipt> archiveSeason({
    required String actorId,
    required String associationId,
    required SeasonModel season,
    required String currentSeasonId,
  }) {
    return _run(
      actorId: actorId,
      associationId: associationId,
      action: 'archive',
      seasonId: season.id,
      request: {
        'schemaVersion': 1,
        'seasonId': season.id,
        'expectedSeasonVersion': season.version,
        'expectedCurrentSeasonId': currentSeasonId,
      },
    );
  }

  Future<SeasonOperationReceipt> restoreSeason({
    required String actorId,
    required String associationId,
    required SeasonModel season,
    required String currentSeasonId,
  }) {
    return _run(
      actorId: actorId,
      associationId: associationId,
      action: 'restore',
      seasonId: season.id,
      request: {
        'schemaVersion': 1,
        'seasonId': season.id,
        'expectedSeasonVersion': season.version,
        'expectedCurrentSeasonId': currentSeasonId,
      },
    );
  }

  Future<SeasonOperationReceipt> _run({
    required String actorId,
    required String associationId,
    required String action,
    required String seasonId,
    required Map<String, Object?> request,
  }) async {
    final operationKey = '$actorId|$associationId|$action|$seasonId';
    final requestFingerprint = jsonEncode(_canonical(request));
    final saved = await _operationStore.load(operationKey);
    if (saved != null && saved.requestFingerprint != requestFingerprint) {
      throw const SeasonWorkflowException(
        'An earlier request may still have completed. Retry that request before changing its details.',
        retryable: false,
      );
    }
    final operation =
        saved ??
        SeasonPendingOperation(
          key: operationKey,
          operationId: _newOperationId(action),
          requestFingerprint: requestFingerprint,
        );
    if (saved == null) await _operationStore.save(operation);

    final payload = <String, Object?>{
      ...request,
      'operationId': operation.operationId,
    };
    try {
      final result = await _invoke('season${_callableSuffix(action)}', payload);
      final receipt = SeasonOperationReceipt.fromMap(result);
      if (receipt.operationId != operation.operationId ||
          receipt.seasonId != seasonId) {
        throw const FormatException(
          'Season operation receipt does not match the saved request.',
        );
      }
      await _operationStore.clear(operationKey);
      return receipt;
    } on FirebaseFunctionsException catch (error) {
      final retryable = const {
        'cancelled',
        'deadline-exceeded',
        'internal',
        'resource-exhausted',
        'unavailable',
        'unknown',
      }.contains(error.code);
      if (!retryable) await _operationStore.clear(operationKey);
      throw SeasonWorkflowException(
        error.message ?? 'The season operation could not be completed.',
        retryable: retryable,
      );
    } on FormatException catch (error) {
      throw SeasonWorkflowException(error.message, retryable: true);
    } catch (error) {
      throw SeasonWorkflowException(
        'The result is uncertain. Check your connection, then retry safely.',
        retryable: true,
        cause: error,
      );
    }
  }

  Future<Map<String, dynamic>> _invoke(
    String name,
    Map<String, Object?> request,
  ) async {
    if (_callable != null) return _callable(name, request);
    final response = await (_functions ?? FirebaseFunctions.instance)
        .httpsCallable(name)
        .call<Map<Object?, Object?>>(request);
    return response.data.map((key, value) => MapEntry(key.toString(), value));
  }

  String _newOperationId(String action) {
    final entropy = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'season_${action}_${DateTime.now().toUtc().microsecondsSinceEpoch}_$entropy';
  }

  static String _callableSuffix(String action) => switch (action) {
    'prepare' => 'Prepare',
    'activate' => 'Activate',
    'archive' => 'Archive',
    'restore' => 'Restore',
    _ => throw StateError('Unknown season action'),
  };

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }
}

class SeasonOperationReceipt {
  final String operationId;
  final String seasonId;
  final String status;
  final int seasonVersion;
  final String? previousSeasonId;
  final String currentSeasonId;

  const SeasonOperationReceipt({
    required this.operationId,
    required this.seasonId,
    required this.status,
    required this.seasonVersion,
    required this.currentSeasonId,
    this.previousSeasonId,
  });

  factory SeasonOperationReceipt.fromMap(Map<String, dynamic> map) {
    final operationId = map['operationId'];
    final seasonId = map['seasonId'];
    final status = map['status'];
    final seasonVersion = map['seasonVersion'];
    final currentSeasonId = map['currentSeasonId'];
    final previousSeasonId = map['previousSeasonId'];
    if (operationId is! String ||
        seasonId is! String ||
        status is! String ||
        seasonVersion is! int ||
        currentSeasonId is! String ||
        (previousSeasonId != null && previousSeasonId is! String)) {
      throw const FormatException('Malformed season operation receipt.');
    }
    return SeasonOperationReceipt(
      operationId: operationId,
      seasonId: seasonId,
      status: status,
      seasonVersion: seasonVersion,
      currentSeasonId: currentSeasonId,
      previousSeasonId: previousSeasonId as String?,
    );
  }
}

class SeasonWorkflowException implements Exception {
  final String message;
  final bool retryable;
  final Object? cause;

  const SeasonWorkflowException(
    this.message, {
    required this.retryable,
    this.cause,
  });

  @override
  String toString() => message;
}

class SeasonPendingOperation {
  final String key;
  final String operationId;
  final String requestFingerprint;

  const SeasonPendingOperation({
    required this.key,
    required this.operationId,
    required this.requestFingerprint,
  });

  Map<String, Object?> toMap() => {
    'key': key,
    'operationId': operationId,
    'requestFingerprint': requestFingerprint,
  };

  factory SeasonPendingOperation.fromMap(Map<String, dynamic> map) {
    return SeasonPendingOperation(
      key: map['key'] as String,
      operationId: map['operationId'] as String,
      requestFingerprint: map['requestFingerprint'] as String,
    );
  }
}

abstract class SeasonOperationStore {
  Future<SeasonPendingOperation?> load(String key);
  Future<void> save(SeasonPendingOperation operation);
  Future<void> clear(String key);
}

class SharedPreferencesSeasonOperationStore implements SeasonOperationStore {
  static const _prefix = 'season_operation_v1_';

  String _storageKey(String key) =>
      '$_prefix${base64Url.encode(utf8.encode(key))}';

  @override
  Future<SeasonPendingOperation?> load(String key) async {
    final raw = (await SharedPreferences.getInstance()).getString(
      _storageKey(key),
    );
    if (raw == null) return null;
    try {
      return SeasonPendingOperation.fromMap(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      throw const SeasonWorkflowException(
        'A saved season request is damaged. Contact support before trying again.',
        retryable: false,
      );
    }
  }

  @override
  Future<void> save(SeasonPendingOperation operation) async {
    await (await SharedPreferences.getInstance()).setString(
      _storageKey(operation.key),
      jsonEncode(operation.toMap()),
    );
  }

  @override
  Future<void> clear(String key) async {
    await (await SharedPreferences.getInstance()).remove(_storageKey(key));
  }
}
