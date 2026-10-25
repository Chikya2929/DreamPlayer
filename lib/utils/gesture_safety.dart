// Safety warnings for the player's brightness / volume swipe gesture.
//
// The gesture can push the volume past 100% (the boost band) and the
// brightness to the top of its range. Both have a consequence worth one brief
// flash: over-amplification can damage small speakers, and a full-brightness
// panel drains the battery faster.
//
// The trigger is PURE so it can be unit-tested: it only ever sees the previous
// and the next gesture value, never the platform.

/// The warning a gesture step can trigger.
enum GestureSafetyWarning {
  /// Nothing to warn about.
  none,

  /// The volume crossed above 100% into the boost band.
  volumeAboveNormal,

  /// The brightness reached the top of its range.
  brightnessFull,
}

/// The gesture value where the volume leaves the system-volume range.
const double kVolumeNormalCeiling = 1.0;

/// The gesture value that counts as full brightness.
const double kBrightnessFullLevel = 1.0;

/// Which safety warning (if any) a gesture step triggers.
///
/// [previous] and [next] are the gesture values before and after the step:
/// 0-2 for volume (100% + boost) and 0-1 for brightness.
///
/// Volume only warns ABOVE 100%, because that is the boost band — with the
/// setting off the gesture is clamped to 100% and never reaches it. The
/// comparison is strict, so a gesture that tops out exactly at 100% (the
/// system maximum, no boost) stays silent.
///
/// Brightness tops out at 100%, so there is no band above it: "increased"
/// means it reached the top of the range.
GestureSafetyWarning gestureSafetyWarning({
  required bool isVolume,
  required double previous,
  required double next,
}) {
  if (isVolume) {
    if (previous <= kVolumeNormalCeiling && next > kVolumeNormalCeiling) {
      return GestureSafetyWarning.volumeAboveNormal;
    }
    return GestureSafetyWarning.none;
  }
  if (previous < kBrightnessFullLevel && next >= kBrightnessFullLevel) {
    return GestureSafetyWarning.brightnessFull;
  }
  return GestureSafetyWarning.none;
}
