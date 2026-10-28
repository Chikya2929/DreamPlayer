import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dream_player/models/video_item.dart';
import 'package:dream_player/services/cast_coordinator.dart';
import 'package:dream_player/widgets/send_to_tv_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SendToTvSheet', () {
    testWidgets('hides the Google row for non-directPlayable sources and offers Stop while casting', (
      tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dreamplayer/multicast'),
        (call) async {
          if (call.method == 'discoverDlna') return <Map<String, dynamic>>[];
          if (call.method == 'discoverDreamCast') return <Map<String, dynamic>>[];
          if (call.method.startsWith('discover')) return <Map<String, dynamic>>[];
          return <Map<String, dynamic>>[];
        },
      );

      final coordinator = CastCoordinator.instance;
      const video = VideoItem(
        id: 'f',
        title: 'Local file',
        duration: Duration(minutes: 5),
        path: '/storage/emulated/0/a.mkv',
      );

      // Start "casting" so the Stop row appears.
      coordinator.active = CastTransport.dlna;
      coordinator.deviceName = 'Living Room TV';
      addTearDown(() {
        coordinator.active = null;
        coordinator.deviceName = null;
      });

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) {
        return Center(
          child: ElevatedButton(
            onPressed: () {
              SendToTvSheet.show(
                context,
                video: video,
                positionMs: 0,
                title: 'Local file',
              );
            },
            child: const Text('open'),
          ),
        );
      }))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSetSettleSafe(tester);

      expect(find.textContaining('Living Room TV'), findsOneWidget);
      // A local file is not a system-Cast candidate and the row is hidden.
      expect(find.text('Chromecast / Google TV…'), findsNothing);
      // No DLNA / DreamCast targets in the mocked discovery — the empty hint.
      expect(find.text('No DreamPlayer or DLNA TVs found on this network.'),
          findsOneWidget);
    });

    testWidgets('shows the Google row for a direct network URL', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dreamplayer/multicast'),
        (call) async => <Map<String, dynamic>>[],
      );
      final coordinator = CastCoordinator.instance;
      coordinator.active = null;

      const video = VideoItem(
        id: 'n',
        title: 'Network video',
        duration: Duration(minutes: 5),
        uri: 'http://192.168.1.16:8096/Videos/stream.mkv',
      );

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) {
        return Center(
          child: ElevatedButton(
            onPressed: () {
              SendToTvSheet.show(
                context,
                video: video,
                positionMs: 0,
                title: 'Network video',
              );
            },
            child: const Text('open'),
          ),
        );
      }))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSetSettleSafe(tester);

      expect(find.text('Chromecast / Google TV…'), findsOneWidget);
    });
  });
}

extension _PumpX on WidgetTester {
  /// pumpAndSettle with the sheet's discovery completed; the polling-free
  /// sheet settles fast.
  Future<void> pumpAndSetSettleSafe(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }
}
