import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/sharing/branded_share_payload.dart';
import 'package:hoops_connect/core/sharing/branded_share_sheet.dart';
import 'package:hoops_connect/models/association_branding_model.dart';

void main() {
  for (final width in [240.0, 358.0, 360.0, 480.0, 1080.0]) {
    for (final long in [false, true]) {
      testWidgets('fixed spotlight zones and equal tiles at $width, long=$long', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1200, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final branding = AssociationBrandingModel.jba().copyWith(
          leagueName: long
              ? 'Jamaica Basketball League National Intercollegiate Championship Association'
              : 'Jamaica Basketball League',
          logoUrl: 'asset:assets/images/jbl_full.png',
          sponsor: const SponsorBrandingModel(
            enabled: true,
            name: 'FOSKA Oats',
            label: 'Main Sponsor',
            logoUrl: 'asset:assets/images/jbl_foska.png',
          ),
        );
        final payload = BrandedSharePayload(
          title: 'Player',
          eyebrow: 'PLAYER SPOTLIGHT',
          headline: long
              ? 'Christopher Alexander Montgomery-Williams Junior'
              : 'KIMARY BROWN',
          teams: [
            BrandedShareTeam(
              name: long
                  ? 'University of the West Indies National Development Basketball Programme'
                  : 'Tivoli Wizards',
              logoUrl: 'asset:assets/images/jbl_tivoli.png',
            ),
          ],
          divisionLabel: '2025 First Round',
          sourceLabel: '2025 First Round · Per-game averages',
          detail: '',
          shareText: '',
          fileName: 'player.png',
          spotlightStats: {
            'GP': long ? '12345' : '9',
            'PPG': long ? '123456.789' : '17.4',
            'RPG': '3.1',
            'APG': '2.2',
            'SPG': '1.8',
            'BPG': '0.0',
          },
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: BrandedShareCard(
                    key: const Key('canvas'),
                    branding: branding,
                    payload: payload,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Rect box(String key) => tester.getRect(find.byKey(Key(key)));
        final scale = width / 360;
        final canvas = box('canvas');
        expect(canvas.height, closeTo(width * 1.25, 0.1));
        final masthead = box('spotlight-masthead');
        expect(
          (masthead.bottom - canvas.top) / canvas.height,
          closeTo(0.08, 0.001),
        );
        final zones = [
          'spotlight-masthead',
          'spotlight-league',
          'spotlight-title',
          'spotlight-identity',
          'spotlight-stat-grid',
          'share-card-footer',
        ].map(box).toList();
        for (var i = 1; i < zones.length; i++) {
          expect(zones[i].top, greaterThanOrEqualTo(zones[i - 1].bottom - 0.1));
          expect(zones[i].bottom, lessThanOrEqualTo(canvas.bottom + 0.1));
        }
        expect(
          box('spotlight-title').top - box('spotlight-league').bottom,
          closeTo(4 * scale, 0.1),
        );
        expect(
          box('spotlight-stat-grid').height / canvas.height,
          closeTo(0.4, 0.001),
        );
        final tiles = [
          'GP',
          'PPG',
          'RPG',
          'APG',
          'SPG',
          'BPG',
        ].map((label) => box('spotlight-tile-$label')).toList();
        for (var i = 0; i < tiles.length; i++) {
          expect(tiles[i].width, closeTo(tiles.first.width, 0.1));
          expect(tiles[i].height, closeTo(tiles.first.height, 0.1));
          for (var j = i + 1; j < tiles.length; j++) {
            expect(tiles[i].overlaps(tiles[j]), isFalse);
          }
        }
        for (final label in ['GP', 'PPG', 'RPG', 'APG', 'SPG', 'BPG']) {
          final tile = box('spotlight-tile-$label'),
              value = box('spotlight-value-$label'),
              caption = box('spotlight-label-$label');
          expect(value.left, greaterThanOrEqualTo(tile.left + 9 * scale));
          expect(value.right, lessThanOrEqualTo(tile.right - 9 * scale));
          expect(value.bottom, lessThanOrEqualTo(caption.top + 0.1));
          expect(caption.bottom, lessThan(tile.bottom));
          if (!long) expect(value.height / scale, greaterThan(25));
        }
        expect(find.text('MAIN SPONSOR'), findsOneWidget);
        expect(find.text('2025 FIRST ROUND'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  test(
    'legacy labelled averages are parsed without inventing missing values',
    () {
      const payload = BrandedSharePayload(
        title: 'Player',
        eyebrow: 'PLAYER SPOTLIGHT',
        headline: 'Player',
        detail: 'Club · 12 GP\n18.7 PPG · 0.0 BPG',
        shareText: '',
        fileName: 'p.png',
      );
      expect(payload.resolvedSpotlightStats, {
        'GP': '12',
        'PPG': '18.7',
        'RPG': 'N/A',
        'APG': 'N/A',
        'SPG': 'N/A',
        'BPG': '0.0',
      });
    },
  );
}
