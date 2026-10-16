import 'dart:math' as math;

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

  group('volumeGestureBase', () {
    // THE REPORTED BUG. Volume below 100%, swipe down, swipe down again: the
    // second swipe restarted from 100% instead of continuing lower.
    test('below 100% the gesture continues from the system volume', () {
      expect(
        volumeGestureBase(systemVolume: 0.3, boost: 1.0, boostEnabled: true),
        0.3,
      );
    });

    test('above 100% the gesture continues from the boost', () {
      expect(
        volumeGestureBase(systemVolume: 1.0, boost: 1.5, boostEnabled: true),
        1.5,
      );
    });

    // The tempting `max(systemVolume, boost)` is WRONG and this pins why:
    // max(0.3, 1.0) == 1.0, so every level under 100% snapped upward.
    test('is not a max of the two (max(0.3, 1.0) would be 1.0)', () {
      final base = volumeGestureBase(
          systemVolume: 0.3, boost: 1.0, boostEnabled: true);
      expect(base, 0.3);
      expect(math.max(0.3, 1.0), 1.0, reason: 'the buggy version would be 1.0');
    });

    test('exactly 100% is unambiguous from either side', () {
      expect(
        volumeGestureBase(systemVolume: 1.0, boost: 1.0, boostEnabled: true),
        1.0,
      );
    });

    // Walking the whole range must never move the base away from the current
    // level, whichever side of 100% it sits on.
    test('base always equals the current effective level', () {
      for (var sys = 0.0; sys <= 1.0; sys += 0.1) {
        expect(
          volumeGestureBase(
              systemVolume: sys, boost: 1.0, boostEnabled: true),
          moreOrLessEquals(sys, epsilon: 1e-9),
          reason: 'no boost active: system $sys must be the base',
        );
      }
      for (var boost = 1.0; boost <= kMaxVolumeBoost; boost += 0.1) {
        expect(
          volumeGestureBase(
              systemVolume: 1.0, boost: boost, boostEnabled: true),
          moreOrLessEquals(boost, epsilon: 1e-9),
          reason: 'boost $boost is active: it must be the base',
        );
      }
    });

    // With boost switched off the gesture is the stock 0-100% and must ignore
    // any stale boost value entirely.
    test('disabled: plain system volume, boost ignored', () {
      expect(
        volumeGestureBase(systemVolume: 0.4, boost: 2.0, boostEnabled: false),
        0.4,
      );
      expect(
        volumeGestureBase(systemVolume: 1.0, boost: 2.0, boostEnabled: false),
        1.0,
      );
    });
  });

  group('volumeCeiling', () {
    test('200% with boost, 100% without', () {
      expect(volumeCeiling(boostEnabled: true), 2.0);
      expect(volumeCeiling(boostEnabled: false), 1.0);
    });
  });

  group('swipeStartBase', () {
    // Regression for issue #41: a brightness swipe was being seeded with the
    // VOLUME base, which returns the boost (2.0 at 200%) instead of the
    // platform brightness. `_applySwipeValue` then clamps (base + delta) to
    // 1.0, so brightness sat pinned at 100% for the whole gesture.
    test('brightness is never seeded from the boost, however high it is', () {
      for (final boost in [1.0, 1.01, 1.5, 2.0]) {
        expect(
          swipeStartBase(
            isVolume: false,
            platformValue: 0.4,
            boost: boost,
            boostEnabled: true,
          ),
          0.4,
          reason: 'brightness base must stay the platform value at boost=$boost',
        );
      }
    });

    test('brightness stays on 0-1 even if the platform reports nonsense', () {
      expect(
        swipeStartBase(
          isVolume: false,
          platformValue: 2.0,
          boost: 2.0,
          boostEnabled: true,
        ),
        1.0,
      );
      expect(
        swipeStartBase(
          isVolume: false,
          platformValue: -1.0,
          boost: 2.0,
          boostEnabled: true,
        ),
        0.0,
      );
    });

    test('volume still uses the boosted base', () {
      expect(
        swipeStartBase(
          isVolume: true,
          platformValue: 0.3,
          boost: 2.0,
          boostEnabled: true,
        ),
        2.0,
      );
      expect(
        swipeStartBase(
          isVolume: true,
          platformValue: 0.3,
          boost: 2.0,
          boostEnabled: false,
        ),
        0.3,
      );
    });

    // The bug only bit because base+delta is clamped to the axis ceiling.
    // Reproduce the actual failure: a downward drag must still darken.
    test('a downward brightness drag lowers brightness below 100%', () {
      double applyBrightness(double base, double delta) =>
          (base + delta).clamp(0.0, 1.0);

      final fixed = swipeStartBase(
        isVolume: false,
        platformValue: 1.0,
        boost: 2.0,
        boostEnabled: true,
      );
      expect(applyBrightness(fixed, -0.4), 0.6);

      // What the old code computed: volume logic applied to brightness.
      final broken = volumeGestureBase(
        systemVolume: 1.0,
        boost: 2.0,
        boostEnabled: true,
      );
      expect(applyBrightness(broken, -0.4), 1.0,
          reason: 'the old base pinned brightness at 100%');
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
}
