import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/admin/association_branding_screen.dart';
import 'package:hoops_connect/models/association_branding_model.dart';
import 'package:hoops_connect/providers/association_branding_providers.dart';

void main() {
  group('AssociationBrandingScreen responsive preview', () {
    for (final width in [375.0, 768.0, 1440.0]) {
      testWidgets('renders safely at ${width.toInt()}px', (tester) async {
        await _pumpScreen(tester, width: width);

        expect(find.byKey(const Key('branding-live-preview')), findsOneWidget);
        expect(find.text('Jamaica Basketball Association'), findsWidgets);
        expect(
          find.text('Sponsor is off. The full league identity remains active.'),
          findsOneWidget,
        );
        expect(find.text('No league logo added.'), findsOneWidget);
        expect(find.textContaining('AA readable'), findsNWidgets(3));
        expect(tester.takeException(), isNull);

        final primary = tester.getTopLeft(_field('Primary color'));
        final dark = tester.getTopLeft(_field('Dark color'));
        final accent = tester.getTopLeft(_field('Accent color'));
        if (width == 375) {
          expect(primary.dy, lessThan(dark.dy));
          expect(dark.dy, lessThan(accent.dy));
        } else if (width == 768) {
          expect(primary.dy, moreOrLessEquals(dark.dy));
          expect(accent.dy, greaterThan(primary.dy));
        } else {
          expect(primary.dy, moreOrLessEquals(dark.dy));
          expect(primary.dy, moreOrLessEquals(accent.dy));
        }
      });
    }

    testWidgets('supports dark mode and large text without overflow', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        width: 375,
        height: 1600,
        themeMode: ThemeMode.dark,
        textScaler: const TextScaler.linear(2),
      );

      expect(find.byKey(const Key('branding-live-preview')), findsOneWidget);
      expect(find.text('Preset palettes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('preview updates with draft while sponsor remains secondary', (
    tester,
  ) async {
    await _pumpScreen(tester, width: 768, height: 1500);

    await tester.enterText(
      _field('Full league or association name'),
      'JBA Pro',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Show title sponsor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show title sponsor'));
    await tester.pump();
    await tester.enterText(_field('Sponsor name'), 'Courtside Co');
    await tester.pump();

    expect(find.text('JBA Pro'), findsWidgets);
    expect(find.text('Sponsor placement'), findsOneWidget);
    expect(
      find.text('Secondary to the Jamaica Basketball identity'),
      findsOneWidget,
    );
    expect(find.text('Courtside Co'), findsOneWidget);
    expect(find.text('No sponsor logo added.'), findsOneWidget);
    expect(find.text('You have unsaved changes.'), findsOneWidget);
  });

  testWidgets('validates colors and logo URLs inline', (tester) async {
    await _pumpScreen(tester, width: 768, height: 1500);

    await tester.enterText(_field('Primary color'), '#12ZZ99');
    await tester.enterText(
      _field('League logo HTTPS URL'),
      'http://example.com/logo.png',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Show title sponsor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show title sponsor'));
    await tester.pump();
    await tester.enterText(
      _field('Sponsor logo HTTPS URL'),
      'logo.example.com/image.png',
    );
    await tester.pump();

    expect(find.text('Primary color must look like #2E7D32'), findsOneWidget);
    expect(find.text('Use a complete HTTPS URL'), findsNWidgets(2));
    expect(find.byKey(const Key('league-logo-invalid')), findsWidgets);
    expect(find.byKey(const Key('sponsor-logo-invalid')), findsOneWidget);
  });

  testWidgets('shows explicit league and sponsor image failure states', (
    tester,
  ) async {
    final branding = AssociationBrandingModel.jba().copyWith(
      logoUrl: 'https://invalid.invalid/league.png',
      sponsor: const SponsorBrandingModel(
        enabled: true,
        logoUrl: 'https://invalid.invalid/sponsor.png',
      ),
    );
    await _pumpScreen(tester, width: 768, height: 1500, branding: branding);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('league-logo-error')), findsWidgets);
    expect(find.byKey(const Key('sponsor-logo-error')), findsOneWidget);
    expect(
      find.text('League logo could not be loaded. Check the URL.'),
      findsOneWidget,
    );
    expect(
      find.text('Sponsor logo could not be loaded. Check the URL.'),
      findsOneWidget,
    );
  });

  testWidgets('maps load failures and offers retry without raw details', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      width: 375,
      stream: Stream<AssociationBrandingModel>.error(
        Exception('UNAVAILABLE internal/project/path'),
      ),
    );
    await tester.pump();

    expect(
      find.text('Check your internet connection and try again'),
      findsOneWidget,
    );
    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.textContaining('internal/project/path'), findsNothing);
  });

  testWidgets('provider refresh preserves dirty edits until user resolves it', (
    tester,
  ) async {
    final controller = StreamController<AssociationBrandingModel>();
    addTearDown(controller.close);
    await _pumpScreen(tester, width: 768, stream: controller.stream);
    controller.add(AssociationBrandingModel.jba());
    await tester.pump();

    await tester.enterText(
      _field('Full league or association name'),
      'My unsaved JBA name',
    );
    await tester.pump();
    controller.add(
      AssociationBrandingModel.jba().copyWith(
        leagueName: 'Saved somewhere else',
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<TextFormField>(_field('Full league or association name'))
          .controller!
          .text,
      'My unsaved JBA name',
    );
    expect(find.text('Saved settings changed elsewhere'), findsOneWidget);
    expect(
      find.text('Resolve the saved-settings update before saving.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(_saveButton()).onPressed, isNull);

    await tester.tap(find.byKey(const Key('use-saved-branding')));
    await tester.pump();
    expect(
      tester
          .widget<TextFormField>(_field('Full league or association name'))
          .controller!
          .text,
      'Saved somewhere else',
    );
    expect(find.text('All branding changes are saved.'), findsOneWidget);
  });

  testWidgets('save is single-flight and confirms the completed write', (
    tester,
  ) async {
    final completer = Completer<void>();
    final stream = StreamController<AssociationBrandingModel>();
    addTearDown(stream.close);
    var saveCalls = 0;
    AssociationBrandingModel? saved;
    await _pumpScreen(
      tester,
      width: 768,
      height: 1500,
      stream: stream.stream,
      onSave: (branding) {
        saveCalls += 1;
        saved = branding;
        return completer.future;
      },
    );
    stream.add(AssociationBrandingModel.jba());
    await tester.pump();

    await tester.enterText(
      _field('Full league or association name'),
      'Jamaica Hoops League',
    );
    await tester.pump();
    await tester.ensureVisible(_saveButton());
    await tester.pumpAndSettle();
    await tester.tap(_saveButton());
    await tester.pump();
    await tester.tap(_saveButton(), warnIfMissed: false);
    await tester.pump();

    expect(saveCalls, 1);
    expect(find.text('Saving branding…'), findsOneWidget);
    expect(saved?.leagueName, 'Jamaica Hoops League');

    stream.add(saved!);
    await tester.pump();
    expect(find.text('Saved settings changed elsewhere'), findsNothing);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text('Branding saved and confirmed'), findsOneWidget);
    expect(find.text('All branding changes are saved.'), findsOneWidget);
  });

  testWidgets('remote updates cannot replace the draft during an in-flight save', (
    tester,
  ) async {
    final stream = StreamController<AssociationBrandingModel>();
    final save = Completer<void>();
    addTearDown(stream.close);
    await _pumpScreen(
      tester,
      width: 768,
      height: 1500,
      stream: stream.stream,
      onSave: (_) => save.future,
    );
    stream.add(AssociationBrandingModel.jba());
    await tester.pump();

    await tester.enterText(
      _field('Full league or association name'),
      'Locally saving name',
    );
    await tester.pump();
    await tester.ensureVisible(_saveButton());
    await tester.pumpAndSettle();
    await tester.tap(_saveButton());
    await tester.pump();

    stream.add(
      AssociationBrandingModel.jba().copyWith(
        leagueName: 'Saved somewhere else',
      ),
    );
    await tester.pump();

    expect(find.text('Saved settings changed elsewhere'), findsOneWidget);
    expect(tester.widget<FilledButton>(_saveButton()).onPressed, isNull);
    expect(
      tester.widget<FilledButton>(
        find.byKey(const Key('use-saved-branding')),
      ).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(
        find.byKey(const Key('keep-branding-edits')),
      ).onPressed,
      isNull,
    );

    save.complete();
    await tester.pumpAndSettle();
    expect(find.text('Saved settings changed elsewhere'), findsOneWidget);
    expect(
      find.text('Resolve the saved-settings update before saving.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextFormField>(_field('Full league or association name'))
          .controller!
          .text,
      'Locally saving name',
    );

    await tester.tap(find.byKey(const Key('use-saved-branding')));
    await tester.pump();
    expect(
      tester
          .widget<TextFormField>(_field('Full league or association name'))
          .controller!
          .text,
      'Saved somewhere else',
    );
  });

  testWidgets('save failure maps the error without exposing raw details', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      width: 768,
      height: 1500,
      onSave: (_) async => throw Exception('permission-denied secret/path'),
    );
    await tester.enterText(_field('Short display name'), 'New JBA');
    await tester.pump();
    await tester.ensureVisible(_saveButton());
    await tester.pumpAndSettle();
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Branding was not saved. You don't have permission to access this",
      ),
      findsOneWidget,
    );
    expect(find.textContaining('secret/path'), findsNothing);
    expect(find.text('You have unsaved changes.'), findsOneWidget);
  });

  testWidgets('leaving with unsaved changes requires confirmation', (
    tester,
  ) async {
    await _setViewport(tester, width: 768, height: 1200);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          associationBrandingProvider.overrideWith(
            (ref) => Stream.value(AssociationBrandingModel.jba()),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AssociationBrandingScreen(),
                    ),
                  ),
                  child: const Text('Open branding'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open branding'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Short display name'), 'Unsaved');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Discard branding changes?'), findsOneWidget);
    expect(find.text('Keep editing'), findsOneWidget);
    expect(find.text('Discard changes'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Branding & Sponsor'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.text('Branding & Sponsor'), findsNothing);
    expect(find.text('Open branding'), findsOneWidget);
  });
}

Finder _field(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextFormField));

Finder _saveButton() => find.byKey(const Key('save-branding-button'));

Future<void> _pumpScreen(
  WidgetTester tester, {
  required double width,
  double height = 1200,
  ThemeMode themeMode = ThemeMode.light,
  TextScaler textScaler = TextScaler.noScaling,
  AssociationBrandingModel? branding,
  Stream<AssociationBrandingModel>? stream,
  BrandingSaveCallback? onSave,
}) async {
  await _setViewport(tester, width: width, height: height);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        associationBrandingProvider.overrideWith(
          (ref) =>
              stream ??
              Stream.value(branding ?? AssociationBrandingModel.jba()),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
        darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        themeMode: themeMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: AssociationBrandingScreen(saveBranding: onSave),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _setViewport(
  WidgetTester tester, {
  required double width,
  required double height,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}
