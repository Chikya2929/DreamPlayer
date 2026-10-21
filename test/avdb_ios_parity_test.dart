import 'dart:io';

import 'package:dream_player/l10n/app_localizations.dart';
import 'package:dream_player/screens/settings_screen.dart';
import 'package:dream_player/services/avdb_adapter.dart';
import 'package:dream_player/services/metadata_provider_adapter.dart';
import 'package:dream_player/services/the_tvdb_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AVDb is shared Dart and `main()` registers it unconditionally, so the iOS
/// build gets exactly the Android behaviour. These tests keep it that way:
///
///  * the Settings control is reachable, toggles and persists when the
///    platform is iOS (not just Android);
///  * nothing in the metadata stack is platform-gated, which is what would
///    silently turn a shared feature into an Android-only one;
///  * the catalogue URL is HTTPS, so the iOS build makes no cleartext request.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    MetadataProviderRegistry.instance.register(AvdbAdapter.instance);
    await AvdbAdapter.instance.setEnabled(false);
    await TheTvdbClient.setProviderChoice(MetadataProviderChoice.tmdb);
  });

  tearDown(() {
    MetadataProviderRegistry.instance.unregister('avdb');
    debugDefaultTargetPlatformOverride = null;
  });

  Widget wrapApp() => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SettingsScreen()),
      );

  Future<void> openMetadata(WidgetTester tester) async {
    await tester.pumpAndSettle();
    final metadata = find.text(
      AppLocalizations.of(tester.element(find.byType(SettingsScreen)))
          .settingsMetadata,
    );
    await tester.ensureVisible(metadata);
    await tester.tap(metadata);
    await tester.pumpAndSettle();
  }

  // The same assertions run on both targets on purpose: if one passes and the
  // other fails, a platform branch has crept into the shared code.
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('AVDb can be selected and enabled on ${platform.name}',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(wrapApp());
      await openMetadata(tester);

      expect(find.text('AVDb'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('providerCell-external')));
      await tester.pumpAndSettle();

      expect(find.text('Enable AVDb'), findsOneWidget);
      final toggle = find.widgetWithText(SwitchListTile, 'Enable AVDb');
      expect(toggle, findsOneWidget);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(await AvdbAdapter.instance.isEnabled(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(avdbPrefsKey), isTrue);
      expect(
        await TheTvdbClient.providerChoice(),
        MetadataProviderChoice.external,
      );

      debugDefaultTargetPlatformOverride = null;
    });
  }

  test('the AVDb catalogue is HTTPS', () {
    expect(
      avdbBaseUrl.startsWith('https://'),
      isTrue,
      reason: 'poster and payload URLs must not require a cleartext exception',
    );
  });

  test('no platform gate exists in the AVDb metadata stack', () {
    final gated = RegExp(
      r'\bPlatform\.is(Android|IOS|Linux|MacOS|Windows|Fuchsia)\b'
      r'|defaultTargetPlatform|kIsWeb',
    );
    for (final path in const [
      'lib/services/avdb_adapter.dart',
      'lib/services/metadata_provider_adapter.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        gated.hasMatch(source),
        isFalse,
        reason: '$path must stay platform-neutral so iOS and Android match',
      );
    }

    // Registration in `main()` is what makes the provider cell appear at all;
    // guarding it by platform would hide AVDb from iOS entirely.
    final entrypoint = File('lib/main.dart').readAsStringSync();
    expect(
      entrypoint.contains(
        'MetadataProviderRegistry.instance.register(AvdbAdapter.instance);',
      ),
      isTrue,
      reason: 'AVDb must be registered unconditionally at startup',
    );
  });
}
