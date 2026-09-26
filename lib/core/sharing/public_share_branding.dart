import '../../models/association_branding_model.dart';
import '../../models/public_league_snapshot.dart';

AssociationBrandingModel publicShareBranding(
  PublicLeagueSnapshot snapshot,
  PublicLeagueDefinition league,
) {
  final associationSponsor = snapshot.effectiveAssociationBrand.sponsor;
  final sponsor = league.sponsor.isActive ? league.sponsor : associationSponsor;
  return AssociationBrandingModel(
    associationId: snapshot.associationId,
    leagueName: league.name,
    shortName: league.shortName,
    logoUrl: league.logoUrl,
    primaryColorHex: league.primaryColorHex,
    secondaryColorHex: league.secondaryColorHex,
    accentColorHex: league.accentColorHex,
    sponsor: _sponsorBranding(
      sponsor,
      associationPartner:
          !league.sponsor.isActive && associationSponsor.isActive,
    ),
  );
}

AssociationBrandingModel publicOverviewShareBranding(
  PublicLeagueSnapshot snapshot,
) {
  final association = snapshot.effectiveAssociationBrand;
  return AssociationBrandingModel(
    associationId: snapshot.associationId,
    leagueName: association.name,
    shortName: association.shortName,
    logoUrl: association.logoUrl,
    primaryColorHex: association.primaryColorHex,
    secondaryColorHex: association.secondaryColorHex,
    accentColorHex: association.accentColorHex,
    sponsor: _sponsorBranding(association.sponsor, associationPartner: true),
  );
}

SponsorBrandingModel _sponsorBranding(
  PublicSponsor sponsor, {
  required bool associationPartner,
}) => SponsorBrandingModel(
  enabled: sponsor.enabled,
  name: sponsor.name,
  label: associationPartner
      ? 'Association partner'
      : sponsor.label == 'Main Sponsor'
      ? 'Main Sponsor'
      : 'Title sponsor',
  logoUrl: sponsor.logoUrl,
  websiteUrl: sponsor.websiteUrl,
);
