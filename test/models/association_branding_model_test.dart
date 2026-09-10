import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/association_branding_model.dart';

void main() {
  group('AssociationBrandingModel', () {
    test('uses Jamaica defaults when branding is absent', () {
      final branding = AssociationBrandingModel.fromMap(
        associationId: 'jba',
        data: const {},
      );

      expect(branding.leagueName, 'Jamaica Basketball Association');
      expect(branding.shortName, 'Jamaica Basketball');
      expect(branding.primaryColorHex, '#2E7D32');
      expect(branding.sponsor.isActive, false);
    });

    test('reads a valid league and sponsor configuration', () {
      final branding = AssociationBrandingModel.fromMap(
        associationId: 'league-1',
        data: const {
          'brandingV1': {
            'leagueName': 'Island Premier League',
            'shortName': 'IPL',
            'logoUrl': 'https://example.com/league.png',
            'primaryColorHex': '#123456',
            'secondaryColorHex': '#234567',
            'accentColorHex': '#FEDCBA',
            'sponsor': {
              'enabled': true,
              'name': 'KFC',
              'label': 'Presented by',
              'logoUrl': 'https://example.com/kfc.png',
              'websiteUrl': 'https://example.com',
            },
          },
        },
      );

      expect(branding.leagueName, 'Island Premier League');
      expect(branding.shortName, 'IPL');
      expect(branding.primaryColorHex, '#123456');
      expect(branding.sponsor.isActive, true);
      expect(branding.sponsor.name, 'KFC');
    });

    test('rejects unsafe URLs and invalid colors', () {
      final branding = AssociationBrandingModel.fromMap(
        associationId: 'league-1',
        data: const {
          'brandingV1': {
            'logoUrl': 'javascript:alert(1)',
            'primaryColorHex': 'green',
            'sponsor': {
              'enabled': true,
              'name': 'Sponsor',
              'logoUrl': 'http://example.com/logo.png',
              'websiteUrl': 'file:///private/data',
            },
          },
        },
      );

      expect(branding.logoUrl, isNull);
      expect(branding.primaryColorHex, '#2E7D32');
      expect(branding.sponsor.logoUrl, isNull);
      expect(branding.sponsor.websiteUrl, isNull);
      expect(branding.sponsor.isActive, true);
    });

    test('serializes a versioned branding map', () {
      final map = AssociationBrandingModel.jba()
          .copyWith(
            sponsor: const SponsorBrandingModel(enabled: true, name: 'KFC'),
          )
          .toBrandingMap();

      expect(map['schemaVersion'], 1);
      expect(map['leagueName'], 'Jamaica Basketball Association');
      expect(map['sponsor'], isA<Map<String, dynamic>>());
      expect((map['sponsor'] as Map<String, dynamic>)['name'], 'KFC');
    });
  });

  group('SponsorBrandingModel', () {
    test('requires both enabled and a name to be active', () {
      expect(const SponsorBrandingModel(enabled: true).isActive, false);
      expect(const SponsorBrandingModel(name: 'KFC').isActive, false);
      expect(
        const SponsorBrandingModel(enabled: true, name: 'KFC').isActive,
        true,
      );
    });

    test('fills an empty sponsor label with Presented by', () {
      const sponsor = SponsorBrandingModel(
        enabled: true,
        name: 'KFC',
        label: '   ',
      );

      expect(sponsor.toMap()['label'], 'Presented by');
    });
  });
}
