import 'package:flutter_test/flutter_test.dart';
import 'package:dream_player/utils/gesture_safety.dart';

void main() {
  group('gestureSafetyWarning', () {
    test('volume crossing above 100% warns', () {
      expect(
        gestureSafetyWarning(isVolume: true, previous: 0.9, next: 1.05),
        GestureSafetyWarning.volumeAboveNormal,
      );
    });

    test('volume crossing from exactly 100% warns', () {
      expect(
        gestureSafetyWarning(isVolume: true, previous: 1.0, next: 1.2),
        GestureSafetyWarning.volumeAboveNormal,
      );
    });

    test('volume stopping at 100% does not warn (no boost band)', () {
      expect(
        gestureSafetyWarning(isVolume: true, previous: 0.9, next: 1.0),
        GestureSafetyWarning.none,
      );
    });

    test('volume staying below 100% does not warn', () {
      expect(
        gestureSafetyWarning(isVolume: true, previous: 0.3, next: 0.8),
        GestureSafetyWarning.none,
      );
    });

    test('volume already above 100% does not re-warn', () {
      expect(
        gestureSafetyWarning(isVolume: true, previous: 1.4, next: 1.6),
        GestureSafetyWarning.none,
      );
    });

    test('volume dropping back below 100% does not warn', () {
      expect(
        gestureSafetyWarning(isVolume: true, previous: 1.6, next: 0.8),
        GestureSafetyWarning.none,
      );
    });

    test('brightness reaching 80% warns', () {
      expect(
        gestureSafetyWarning(isVolume: false, previous: 0.6, next: 0.8),
        GestureSafetyWarning.brightnessHigh,
      );
    });

    test('brightness crossing above 80% warns', () {
      expect(
        gestureSafetyWarning(isVolume: false, previous: 0.79, next: 0.9),
        GestureSafetyWarning.brightnessHigh,
      );
    });

    test('brightness below 80% does not warn', () {
      expect(
        gestureSafetyWarning(isVolume: false, previous: 0.4, next: 0.79),
        GestureSafetyWarning.none,
      );
    });

    test('brightness already at 80% does not re-warn', () {
      expect(
        gestureSafetyWarning(isVolume: false, previous: 0.8, next: 0.9),
        GestureSafetyWarning.none,
      );
    });

    test('brightness dropping does not warn', () {
      expect(
        gestureSafetyWarning(isVolume: false, previous: 0.9, next: 0.5),
        GestureSafetyWarning.none,
      );
    });
  });
}
