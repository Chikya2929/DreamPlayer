import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dream_player/services/app_updater.dart';
import 'package:dream_player/widgets/update_dialog.dart';

const _update = AvailableUpdate(
  version: '0.5.5',
  installedVersion: '0.5.4',
  notes: 'Added\n\u2022 Library search',
  assetUrl:
      'https://github.com/mangeshghodke/DreamPlayer/releases/download/v0.5.5/'
      'DreamPlayer-0.5.5-arm64-v8a.apk',
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppUpdateDialog(context, _update),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows both versions, the notes and the actions', (tester) async {
    await _pump(tester);

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('v0.5.4'), findsOneWidget);
    expect(find.text('v0.5.5'), findsOneWidget);
    expect(find.text("What's new"), findsOneWidget);
    expect(find.textContaining('Library search'), findsOneWidget);
    expect(find.text('Download & install'), findsOneWidget);
    expect(find.text('Skip this version'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('skipping remembers the version and closes', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Skip this version'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('dreamplayer.skippedUpdateVersion'), '0.5.5');
  });

  testWidgets('lays out on a phone with large text without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pump(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Download & install'), findsOneWidget);
  });
}
