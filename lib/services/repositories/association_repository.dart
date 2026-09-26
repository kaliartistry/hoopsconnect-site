import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firestore_paths.dart';
import '../../models/association_branding_model.dart';
import '../../models/division_model.dart';
import '../../models/league_catalog_model.dart';

class AssociationRepository {
  final FirebaseFirestore _db;

  AssociationRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  DocumentReference<AssociationBrandingModel> _brandingRef(
    String associationId,
  ) {
    return _db
        .doc(FirestorePaths.association(associationId))
        .withConverter<AssociationBrandingModel>(
          fromFirestore: (snapshot, _) => AssociationBrandingModel.fromMap(
            associationId: snapshot.id,
            data: snapshot.data() ?? const <String, dynamic>{},
          ),
          toFirestore: (branding, _) => {
            'brandingV1': branding.toBrandingMap(),
          },
        );
  }

  Stream<AssociationBrandingModel> watchBranding(String associationId) {
    return _brandingRef(associationId).snapshots().map((snapshot) {
      return snapshot.data() ??
          AssociationBrandingModel.jba(associationId: associationId);
    });
  }

  Stream<LeagueCatalogModel> watchLeagueCatalog(String associationId) {
    return _db
        .doc(FirestorePaths.association(associationId))
        .snapshots()
        .map(
          (snapshot) => LeagueCatalogModel.fromAssociationMap(
            snapshot.data() ?? const <String, dynamic>{},
          ),
        );
  }

  Future<void> saveBranding(AssociationBrandingModel branding) async {
    await _db.doc(FirestorePaths.association(branding.associationId)).set({
      'brandingV1': branding.toBrandingMap(),
      'brandingUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveLeagueCatalog({
    required String associationId,
    required LeagueCatalogModel catalog,
  }) async {
    final validated = LeagueCatalogModel.fromAssociationMap({
      'leagueCatalogV1': catalog.toMap(),
    });
    await _db.doc(FirestorePaths.association(associationId)).set({
      'leagueCatalogV1': validated.toMap(),
      'leagueCatalogUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Creates a division and attaches it to its parent league in one atomic
  /// write. A division cannot be created without an active parent league.
  Future<String> createDivisionUnderLeague({
    required String associationId,
    required String leagueId,
    required String name,
    String? description,
    String? seasonId,
  }) async {
    final associationRef = _db.doc(FirestorePaths.association(associationId));
    final divisionRef = _db
        .collection(FirestorePaths.divisions(associationId))
        .doc();

    await _db.runTransaction((transaction) async {
      final association = await transaction.get(associationRef);
      if (!association.exists) throw StateError('Association not found.');
      final catalog = LeagueCatalogModel.fromAssociationMap(
        association.data() ?? const <String, dynamic>{},
      );
      final parentIndex = catalog.leagues.indexWhere(
        (league) => league.id == leagueId && !league.isArchived,
      );
      if (parentIndex < 0) {
        throw StateError('Choose an active parent league.');
      }

      final parent = catalog.leagues[parentIndex];
      final updatedParent = parent.copyWith(
        divisionIds: [...parent.divisionIds, divisionRef.id],
      );
      final updatedLeagues = [...catalog.leagues];
      updatedLeagues[parentIndex] = updatedParent;
      final updatedCatalog = LeagueCatalogModel(leagues: updatedLeagues);
      final division = DivisionModel(
        id: divisionRef.id,
        name: name,
        leagueId: leagueId,
        seasonId: seasonId,
        description: description,
      );

      transaction.set(divisionRef, division.toFirestore());
      transaction.update(associationRef, {
        'leagueCatalogV1': updatedCatalog.toMap(),
        'leagueCatalogUpdatedAt': FieldValue.serverTimestamp(),
      });
    });
    return divisionRef.id;
  }

  /// Updates a division while keeping the division document and its one parent
  /// league catalog entry synchronized.
  Future<void> updateDivisionUnderLeague({
    required String associationId,
    required String divisionId,
    required String leagueId,
    required String name,
    String? description,
  }) async {
    final associationRef = _db.doc(FirestorePaths.association(associationId));
    final divisionRef = _db.doc(
      FirestorePaths.division(associationId, divisionId),
    );

    await _db.runTransaction((transaction) async {
      final snapshots = await Future.wait([
        transaction.get(associationRef),
        transaction.get(divisionRef),
      ]);
      final association = snapshots[0];
      final division = snapshots[1];
      if (!association.exists || !division.exists) {
        throw StateError('League or division not found.');
      }
      final catalog = LeagueCatalogModel.fromAssociationMap(
        association.data() ?? const <String, dynamic>{},
      );
      if (!catalog.leagues.any(
        (league) => league.id == leagueId && !league.isArchived,
      )) {
        throw StateError('Choose an active parent league.');
      }
      final updatedLeagues = [
        for (final league in catalog.leagues)
          league.copyWith(
            divisionIds: {
              for (final id in league.divisionIds)
                if (id != divisionId) id,
              if (league.id == leagueId) divisionId,
            }.toList(growable: false),
          ),
      ];
      final storedVersion = division.data()?['version'];
      if (storedVersion is! int || storedVersion < 1) {
        throw StateError(
          'Division must be migrated to a versioned record before editing.',
        );
      }

      transaction.update(associationRef, {
        'leagueCatalogV1': LeagueCatalogModel(leagues: updatedLeagues).toMap(),
        'leagueCatalogUpdatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(divisionRef, {
        'name': name,
        'description': description,
        'leagueId': leagueId,
        'version': storedVersion + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
