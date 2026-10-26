import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins the order of the center transport cluster.
///
/// The row reads: previous chapter · back 10 s · play/pause · forward 10 s ·
/// next chapter. The chapter arrows bracket the ±10 s pair, so the row reads
/// left-to-right like a record player and the "previous" button is the first
/// one a viewer reaches for.
///
/// The cluster is read out of the source instead of pumped as a widget: the
/// player screen needs a live platform view, and the order is a property of
/// the source tree, not of the rendered pixels.
void main() {
  test('the center transport cluster keeps its button order', () {
    final source = File('lib/screens/player_screen.dart').readAsStringSync();

    final start = source.indexOf('// Chapter jump, beside play/pause');
    final end = source.indexOf('if (_chapterToast != null)');
    expect(start, greaterThan(-1), reason: 'the transport cluster moved');
    expect(end, greaterThan(start), reason: 'the transport cluster moved');

    final cluster = source.substring(start, end);

    final previous = cluster.indexOf('Icons.skip_previous');
    final back10 = cluster.indexOf('Icons.replay_10');
    final playPause = cluster.indexOf('_playPauseFocusNode');
    final forward10 = cluster.indexOf('Icons.forward_10');
    final next = cluster.indexOf('Icons.skip_next');

    final positions = {
      'skip_previous': previous,
      'replay_10': back10,
      'play/pause': playPause,
      'forward_10': forward10,
      'skip_next': next,
    };
    positions.forEach((label, offset) {
      expect(offset, greaterThan(-1), reason: '$label left the cluster');
    });

    expect(previous, lessThan(back10));
    expect(back10, lessThan(playPause));
    expect(playPause, lessThan(forward10));
    expect(forward10, lessThan(next));
  });
}
