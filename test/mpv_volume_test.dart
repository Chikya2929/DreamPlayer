import 'package:flutter_test/flutter_test.dart';

import 'package:dream_player/utils/mpv_volume.dart';

void main() {
  group('splitVolume', () {
    // The model the user asked for: swipe to 100% as normal, keep going and the
    // extra travel becomes boost.
    test('below 100% is plain system volume with no boost', () {
      expect(splitVolume(0.6, boostEnabled: true), const VolumeSplit(0.6, 1.0));
      expect(splitVolume(0.0, boostEnabled: true), const VolumeSplit(0.0, 1.0));
    });

    test('100% is exactly the handover point', () {
      expect(splitVolume(1.0, boostEnabled: true), const VolumeSplit(1.0, 1.0));
    });

    test('past 100% the system volume pins at max and the rest is boost', () {
      expect(splitVolume(1.5, boostEnabled: true), const VolumeSplit(1.0, 1.5));
      expect(splitVolume(2.0, boostEnabled: true), const VolumeSplit(1.0, 2.0));
    });

    // The split is the whole point: multiplying would let the OS volume exceed
    // 100%, which the platform clamps, and would drop the gesture back to 0
    // when it went above 100% instead of carrying the boost.
    test('system volume never exceeds 100%', () {
      for (var v = 0.0; v <= 2.0; v += 0.05) {
        expect(splitVolume(v, boostEnabled: true).system, lessThanOrEqualTo(1.0));
      }
    });

    test('boost never leaves 1.0..2.0', () {
      for (var v = 0.0; v <= 4.0; v += 0.05) {
        final b = splitVolume(v, boostEnabled: true).boost;
        expect(b, greaterThanOrEqualTo(1.0));
        expect(b, lessThanOrEqualTo(kMaxVolumeBoost));
      }
    });

    // Switching the setting off must restore stock behaviour exactly, not
    // merely hide the boost.
    test('boost disabled clamps to 100% and pins boost at 1.0', () {
      expect(splitVolume(1.8, boostEnabled: false), const VolumeSplit(1.0, 1.0));
      expect(splitVolume(0.4, boostEnabled: false), const VolumeSplit(0.4, 1.0));
    });

    test('round trip: level -> split -> level is stable', () {
      for (final v in [0.0, 0.25, 1.0, 1.75, 2.0]) {
        final s = splitVolume(v, boostEnabled: true);
        expect(s.system + (s.boost - 1.0), closeTo(v, 1e-9),
            reason: 'gesture value $v must survive the split');
      }
    });
  });

  group('volumeCeiling', () {
    test('200% with boost, 100% without', () {
      expect(volumeCeiling(boostEnabled: true), 2.0);
      expect(volumeCeiling(boostEnabled: false), 1.0);
    });
  });

  group('mpvVolumePercent', () {
    test('no boost is just the system volume', () {
      expect(mpvVolumePercent(baseFraction: 1.0, boost: 1.0, nightMode: false), 100);
      expect(mpvVolumePercent(baseFraction: 0.6, boost: 1.0, nightMode: false), 60);
      expect(mpvVolumePercent(baseFraction: 0.0, boost: 1.0, nightMode: false), 0);
    });

    // The #41 report: boost must actually reach mpv. The gain lives HERE, on
    // the `volume` property, because a filter-based gain is discarded on an
    // audiotrack output (measured: `af` reads back empty).
    test('boost scales the base volume', () {
      expect(mpvVolumePercent(baseFraction: 1.0, boost: 2.0, nightMode: false), 200);
      expect(mpvVolumePercent(baseFraction: 0.5, boost: 2.0, nightMode: false), 100);
    });

    // The regression the reporter found: the swipe gesture wrote the raw base
    // through, so any swipe silently discarded the boost.
    test('swiping volume KEEPS the boost instead of wiping it', () {
      const boost = 2.0;
      expect(mpvVolumePercent(baseFraction: 0.6, boost: boost, nightMode: false), 120);
      final full = mpvVolumePercent(baseFraction: 1.0, boost: boost, nightMode: false);
      final half = mpvVolumePercent(baseFraction: 0.5, boost: boost, nightMode: false);
      expect(half, closeTo(full / 2, 0.001));
    });

    test('night mode stacks on top of boost', () {
      expect(mpvVolumePercent(baseFraction: 1.0, boost: 1.0, nightMode: true), 160);
      expect(mpvVolumePercent(baseFraction: 1.0, boost: 1.25, nightMode: true), 200);
    });

    test('ignores a negligible boost so it cannot nudge the volume', () {
      expect(mpvVolumePercent(baseFraction: 1.0, boost: 1.005, nightMode: false), 100);
    });

    test('clamps at the fixed ceiling', () {
      expect(mpvVolumePercent(baseFraction: 1.0, boost: 3.0, nightMode: true), kMpvVolumeMax);
      expect(mpvVolumePercent(baseFraction: 1.0, boost: 10.0, nightMode: false), kMpvVolumeMax);
    });

    test('never returns a negative volume', () {
      expect(mpvVolumePercent(baseFraction: -1.0, boost: 2.0, nightMode: false), 0);
    });
  });

  group('mpvBoostFilter', () {
    test('no boost means no filter at all', () {
      expect(mpvBoostFilter(1.0, nightMode: false), isNull);
      expect(mpvBoostFilter(1.005, nightMode: false), isNull);
    });

    // No gain in the filter. Putting it there AND on `volume` would double the
    // boost; putting it only there means no boost at all on this build.
    test('carries the limiter only, never gain', () {
      final f = mpvBoostFilter(2.0, nightMode: false)!;
      expect(f, isNot(contains('volume=')));
      expect(f, contains('alimiter='));
    });

    // Because the string is constant, the volume gesture stops rebuilding
    // mpv's filter graph on every drag frame.
    test('is identical for any boost, so the graph is not rebuilt per frame', () {
      expect(mpvBoostFilter(1.2, nightMode: false),
          mpvBoostFilter(2.0, nightMode: false));
    });

    test('the graph is quoted so af does not split on an inner comma', () {
      final f = mpvBoostFilter(2.0, nightMode: false)!;
      expect(f, startsWith("lavfi='["));
      expect(f, endsWith("]'"));
      expect(RegExp(r"^[^']*'[^']*'$").hasMatch(f), isTrue,
          reason: 'exactly one quoted section, so exactly one list item');
    });

    test('the limiter caps below full scale so peaks are limited, not clipped', () {
      final f = mpvBoostFilter(2.0, nightMode: false)!;
      expect(f, contains('limit=$kMpvLimitCeiling'));
      expect(kMpvLimitCeiling, lessThan(1.0));
    });

    test('night mode keeps the limiter attached', () {
      expect(mpvBoostFilter(1.5, nightMode: true), isNotNull);
    });
  });
}
