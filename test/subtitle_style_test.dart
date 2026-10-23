import 'package:dream_player/screens/subtitle_settings_screen.dart';
import 'package:dream_player/services/subtitle_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SubtitleStyle', () {
    test('defaults', () {
      const style = SubtitleStyle();
      expect(style.sizeMultiplier, 1.0);
      expect(style.font, SubtitleFont.system);
      expect(style.colorValue, 0xFFFFFFFF);
      expect(style.textOpacity, 255);
      expect(style.backgroundColorValue, 0x80000000);
      expect(style.backgroundOpacity, 128);
      expect(style.edge, SubtitleEdge.outline);
      expect(style.outline, isTrue);
      expect(style.delayMs, 0);
      expect(style.hasBackground, isTrue);
    });

    test('text and background opacity reach the effective colors', () {
      const style = SubtitleStyle(
        colorValue: 0xFFFFEB3B,
        textOpacity: 128,
        backgroundColorValue: 0xFF1A237E,
        backgroundOpacity: 64,
      );
      expect(style.effectiveTextColor, 0x80FFEB3B);
      expect(style.effectiveBackgroundColor, 0x401A237E);
    });

    test('no-background detection (alpha 0)', () {
      const style = SubtitleStyle(backgroundColorValue: 0x00000000);
      expect(style.hasBackground, isFalse);
    });

    test('json round-trip preserves the new fields', () async {
      SharedPreferences.setMockInitialValues({});
      const original = SubtitleStyle(
        sizeMultiplier: 1.25,
        font: SubtitleFont.serif,
        colorValue: 0xFFFFEB3B,
        textOpacity: 200,
        backgroundColorValue: 0xF01A237E,
        backgroundOpacity: 90,
        edge: SubtitleEdge.dropShadow,
        delayMs: 1500,
      );
      await original.save();
      final loaded = await SubtitleStyle.load();
      expect(loaded.sizeMultiplier, original.sizeMultiplier);
      expect(loaded.font, SubtitleFont.serif);
      expect(loaded.colorValue, original.colorValue);
      expect(loaded.textOpacity, 200);
      expect(loaded.backgroundColorValue, original.backgroundColorValue);
      expect(loaded.backgroundOpacity, 90);
      expect(loaded.edge, SubtitleEdge.dropShadow);
      expect(loaded.delayMs, original.delayMs);
    });

    test('legacy json with only a boolean outline still loads', () {
      final off = SubtitleStyle.fromJson({'outline': false});
      expect(off.edge, SubtitleEdge.none);
      expect(off.font, SubtitleFont.system);
      expect(off.textOpacity, 255);

      final on = SubtitleStyle.fromJson({'outline': true});
      expect(on.edge, SubtitleEdge.outline);
    });

    test('unknown font/edge strings fall back safely', () {
      final style = SubtitleStyle.fromJson({'font': 'wingdings', 'edge': 'x'});
      expect(style.font, SubtitleFont.system);
      expect(style.edge, SubtitleEdge.outline);
    });

    test('corrupt json falls back to defaults', () async {
      SharedPreferences.setMockInitialValues({
        'dreamplayer.subStyle': '{not json',
      });
      final loaded = await SubtitleStyle.load();
      expect(loaded.sizeMultiplier, 1.0);
      expect(loaded.delayMs, 0);
      expect(loaded.edge, SubtitleEdge.outline);
    });

    test('channel args carry every field natively typed', () {
      const style = SubtitleStyle(
        sizeMultiplier: 1.5,
        font: SubtitleFont.casual,
        colorValue: 0xFF80DEEA,
        textOpacity: 128,
        backgroundColorValue: 0x00000000,
        edge: SubtitleEdge.raised,
        delayMs: -2000,
      );
      final args = style.toChannelArgs();
      expect(args['size'], 1.5);
      expect(args['font'], 'casual');
      expect(args['color'], 0x8080DEEA);
      expect(args['bg'], 0x00000000);
      expect(args['edge'], 'raised');
      expect(args['delayMs'], -2000);
      expect(args['vPos'], 20);
    });

    test('delay clamps to the supported window', () {
      expect(SubtitleStyle.minDelayMs, -30000);
      expect(SubtitleStyle.maxDelayMs, 30000);
      const style = SubtitleStyle(delayMs: 30000);
      expect(style.delaySeconds, 30.0);
    });
  });

  group('SubtitleSettingsScreen', () {
    testWidgets('renders every YouTube-style section and the preview', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: SubtitleSettingsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Sample subtitle line'), findsOneWidget);
      expect(find.text('Subtitles'), findsOneWidget); // app bar
      for (final section in [
        'Font',
        'Text size',
        'Text color',
        'Text opacity',
        'Background',
        'Background opacity',
        'Edge style',
        'Position',
        'Delay',
      ]) {
        expect(find.text(section), findsOneWidget, reason: section);
      }
    });

    testWidgets('font and edge dropdowns persist their choice', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: SubtitleSettingsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<SubtitleFont>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Serif').last);
      await tester.pumpAndSettle();
      expect((await SubtitleStyle.load()).font, SubtitleFont.serif);

      await tester.tap(find.byType(DropdownButtonFormField<SubtitleEdge>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drop shadow').last);
      await tester.pumpAndSettle();
      expect((await SubtitleStyle.load()).edge, SubtitleEdge.dropShadow);
    });

    testWidgets('text color shows a selected check and persists a pick', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: SubtitleSettingsScreen()));
      await tester.pumpAndSettle();

      // Regression: the stored color is RGB + a separate opacity. Comparing
      // full ARGB against the swatch's 0xFF alpha meant the default White was
      // never marked selected and no swatch ever showed its check.
      Finder chipFor(String label) => find
          .ancestor(of: find.text(label).first, matching: find.byType(InkWell))
          .first;
      expect(
        find.descendant(of: chipFor('White'), matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );

      await tester.tap(find.text('Pink'));
      await tester.pumpAndSettle();
      expect(
        (await SubtitleStyle.load()).colorValue & 0x00FFFFFF,
        0x00FF80AB,
      );
      expect(
        find.descendant(of: chipFor('Pink'), matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: chipFor('White'),
          matching: find.byIcon(Icons.check),
        ),
        findsNothing,
      );
    });

    testWidgets('updates delay via the last slider and resets everything', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: SubtitleSettingsScreen()));
      await tester.pumpAndSettle();

      final sliders = find.byType(Slider);
      await tester.scrollUntilVisible(
        sliders.last,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(sliders.last);
      await tester.dragFrom(
        rect.centerLeft + const Offset(12, 0),
        Offset((rect.width - 24) * 0.8, 0),
      );
      await tester.pumpAndSettle();
      expect((await SubtitleStyle.load()).delayMs, greaterThan(0));

      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await tester.pumpAndSettle();
      expect((await SubtitleStyle.load()).delayMs, 0);
      expect((await SubtitleStyle.load()).edge, SubtitleEdge.outline);
    });

    testWidgets('no overflow at small phone size with large text scale', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(const MaterialApp(home: SubtitleSettingsScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('landscape short viewport does not throw (clamp regression)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      // Landscape phone: 26% of 360 < the old 96px floor triggered
      // ArgumentError from clamp().
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: SubtitleSettingsScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
