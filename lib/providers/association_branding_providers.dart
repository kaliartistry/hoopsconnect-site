import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../models/association_branding_model.dart';
import '../services/repositories/association_repository.dart';
import 'auth_providers.dart';

final associationRepositoryProvider = Provider<AssociationRepository>((ref) {
  return AssociationRepository();
});

final associationBrandingProvider = StreamProvider<AssociationBrandingModel>((
  ref,
) {
  final associationId = ref.watch(currentAssociationIdProvider);
  if (associationId == null) {
    return Stream.value(AssociationBrandingModel.jba());
  }
  return ref.watch(associationRepositoryProvider).watchBranding(associationId);
});

final effectiveAssociationBrandingProvider = Provider<AssociationBrandingModel>(
  (ref) {
    return ref.watch(associationBrandingProvider).valueOrNull ??
        AssociationBrandingModel.jba(
          associationId:
              ref.watch(currentAssociationIdProvider) ??
              AppDefaults.defaultAssociationId,
        );
  },
);
