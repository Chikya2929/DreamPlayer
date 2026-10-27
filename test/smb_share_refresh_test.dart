import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dream_player/screens/smb_screen.dart';

import 'test_helper.dart';

/// Regression for the iOS report: logging in showed the share list, but
/// pull-to-refresh on that list errored with "Could not read that folder".
///
/// The shares view reuses `_flatFileList`, whose refresh handler called
/// `_loadDirectory('')`; that sends `listDirectory` with an EMPTY share, and
/// libsmb2 cannot tree-connect to an empty share name. The log showed exactly
/// that: `invalidateListingCache` followed by
/// `listDirectory {share: "", path: ""}`. Refreshing at the shares level must
/// re-run `listShares`, never `listDirectory`.
void main() {
  const channel = MethodChannel('dreamplayer/smb');

  Map<String, Object?> server() => {
        'id': 'server-1',
        'name': 'NAS',
        'host': '192.168.1.16',
        'port': 445,
        'username': 'mangesh',
        'domain': '',
        'anonymous': false,
        'hasPassword': true,
      };

  Map<String, Object?> shareEntry() => {
        'name': 'downloads',
        'path': 'downloads',
        'isDirectory': true,
        'size': 0,
        'modified': 0,
      };

  Future<List<MethodCall>> pumpShares(
    WidgetTester tester, {
    List<MethodCall>? sink,
  }) async {
    final calls = sink ?? <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'listServers':
          return [server()];
        case 'checkServer':
          return true;
        case 'listShares':
          return [shareEntry()];
        case 'invalidateListingCache':
        case 'closeShare':
          return null;
        case 'listDirectory':
          // The bug: an empty share reaches the native side and fails.
          throw PlatformException(
            code: 'smb',
            message: 'Could not read that folder',
          );
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(localizedApp(const SmbScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('NAS'));
    await tester.pumpAndSettle();
    expect(find.text('downloads'), findsOneWidget);
    return calls;
  }

  testWidgets('pull-to-refresh on the share list re-lists shares', (tester) async {
    final calls = await pumpShares(tester);
    final sharesBefore =
        calls.where((c) => c.method == 'listShares').length;

    await tester.fling(find.text('downloads'), const Offset(0, 320), 1200);
    await tester.pumpAndSettle();

    expect(
      calls.where((c) => c.method == 'listShares').length,
      greaterThan(sharesBefore),
    );
    expect(
      calls.where((c) => c.method == 'listDirectory'),
      isEmpty,
      reason: 'refreshing the shares level must not list a directory',
    );
    expect(find.text('downloads'), findsOneWidget);
    expect(find.textContaining('Could not read'), findsNothing);
  });

  testWidgets('Retry at the shares level reloads shares, not the server list',
      (tester) async {
    var shareAttempts = 0;
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'listServers':
          return [server()];
        case 'checkServer':
          return true;
        case 'listShares':
          shareAttempts++;
          if (shareAttempts == 1) {
            throw PlatformException(
              code: 'smb',
              message: 'Could not list shares',
            );
          }
          return [shareEntry()];
        case 'invalidateListingCache':
        case 'closeShare':
          return null;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(localizedApp(const SmbScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('NAS'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not list shares'), findsOneWidget);

    final listsBefore = calls.where((c) => c.method == 'listServers').length;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('downloads'), findsOneWidget);
    expect(
      calls.where((c) => c.method == 'listServers').length,
      listsBefore,
      reason: 'Retry must not fall back to reloading the server list',
    );
  });
}
