import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/sharing/branded_share_payload.dart';
import 'package:hoops_connect/core/sharing/branded_share_sheet.dart';
import 'package:hoops_connect/models/association_branding_model.dart';

void main() {
  testWidgets('share card keeps league, sponsor, and app identity visible', (
    tester,
  ) async {
    final branding = AssociationBrandingModel.jba().copyWith(
      sponsor: const SponsorBrandingModel(enabled: true, name: 'KFC'),
    );
    const payload = BrandedSharePayload(
      title: 'Game result',
      headline: 'Kingston Titans defeat Montego Bay Storm 87-72',
      detail: 'A complete game summary.',
      shareText: 'Share text',
      fileName: 'result.png',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: BrandedShareCard(branding: branding, payload: payload),
            ),
          ),
        ),
      ),
    );

    expect(find.text('JAMAICA BASKETBALL ASSOCIATION'), findsOneWidget);
    expect(find.text('Presented by KFC'), findsOneWidget);
    expect(find.text('HOOPSCONNECT'), findsOneWidget);
    expect(find.text('FINAL'), findsOneWidget);
    expect(find.textContaining('87-72'), findsOneWidget);
  });
}
