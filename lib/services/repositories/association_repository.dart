import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firestore_paths.dart';
import '../../models/association_branding_model.dart';
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
}
