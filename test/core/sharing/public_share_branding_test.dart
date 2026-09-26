import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/sharing/public_share_branding.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';

void main() {
  final version = PublicSnapshotVersion(
    schemaVersion: 1,
    contractVersion: 'legacy-public-snapshot-v1.1',
    snapshotVersion: null,
    verificationStatus: 'legacyApproved',
    state: PublicReleaseState.published,
    privacyEpoch: 1,
    generatedAt: DateTime.utc(2026, 9, 15),
  );

  PublicLeagueSnapshot snapshot({required PublicSponsor leagueSponsor}) =>
      PublicLeagueSnapshot(
        leagueName: 'Jamaica Basketball Association',
        leagueShortName: 'JBA',
        seasonId: '2026',
        version: version,
        associationBrand: const PublicBrandIdentity(
          name: 'Jamaica Basketball Association',
          shortName: 'JBA',
          sponsor: PublicSponsor(
            enabled: true,
            name: 'Association Partner',
            logoUrl: 'asset:assets/images/sponsor_kingston_flame.png',
          ),
        ),
        leagues: [
          PublicLeagueDefinition(
            leagueId: 'womens',
            name: 'Women’s League',
            shortName: 'Women’s',
            sponsor: leagueSponsor,
          ),
        ],
        schedule: const [],
        standings: const [],
        leaderboards: const [],
      );

  test('league title sponsor takes precedence on league share cards', () {
    final data = snapshot(
      leagueSponsor: const PublicSponsor(
        enabled: true,
        name: 'Bank of Kingston',
        logoUrl: 'asset:assets/images/sponsor_bank_of_kingston.png',
      ),
    );
    final branding = publicShareBranding(data, data.availableLeagues.first);
    expect(branding.sponsor.name, 'Bank of Kingston');
    expect(branding.sponsor.label, 'Title sponsor');
  });

  test('association partner fills unsponsored league share cards', () {
    final data = snapshot(leagueSponsor: const PublicSponsor());
    final branding = publicShareBranding(data, data.availableLeagues.first);
    expect(branding.sponsor.name, 'Association Partner');
    expect(branding.sponsor.label, 'Association partner');
  });

  test('mixed league overview uses association branding and partner', () {
    final data = snapshot(leagueSponsor: const PublicSponsor());
    final branding = publicOverviewShareBranding(data);
    expect(branding.leagueName, 'Jamaica Basketball Association');
    expect(branding.sponsor.name, 'Association Partner');
    expect(branding.sponsor.label, 'Association partner');
  });
}
