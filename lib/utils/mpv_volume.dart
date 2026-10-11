// Volume model shared by the Media3 and MPV engines, and by the swipe
// gesture that drives them.
//
// ## Why boost is a gesture band and not a slider
//
// Boost is the 100-200% half of the volume gesture. The user swipes up to
// 100% as usual, keeps going, and past 100% the extra travel becomes
// over-amplification instead of system volume. It is gated behind
// Settings -> Audio -> Volume boost, because silently amplifying past 100%
// is not something to opt everyone into.
//
// ## Why the boost is staged differently per engine
//
// Media3 has a real effect chain, so `DynamicsBoost` applies a compressor
// followed by a limiter (#41: `LoudnessEnhancer` clipped audibly from ~6 dB
// and crushed dialogue out of the mix).
//
// MPV has no comparable hardware effect. Its gain therefore rides on mpv's own
// `volume` property, which is the one placement known to actually reach the
// speaker — a filter-based gain is discarded on an `audiotrack` output
// (measured on-device: `af` reads back empty). The limiter is still attached
// best-effort so a working build gets smoothing, but MPV must never *depend*
// on the filter for the boost to exist.
//
// `mpvVolumePercent` is the single place that decides the number, so the swipe
// gesture, night mode and the per-open apply cannot drift apart (#41: they
// once did, and the reporter described it as "boost works until I touch
// volume").

/// Ceiling of the gesture's boost band. 100-200% maps to 1.0x-2.0x.
const double kMaxVolumeBoost = 2.0;

/// Gesture ceiling when boost is switched off: plain system volume, 0-100%.
const double kMaxVolumeNoBoost = 1.0;

/// Ceiling for mpv's `volume`. Fixed rather than tracking the current value:
/// mpv clamps `volume` to `volume-max`, so a ceiling that moved with the boost
/// would silently clamp the volume gesture the moment it pushed past the last
/// boosted value.
const double kMpvVolumeMax = 400.0;

/// True peak ceiling for the MPV limiter, ~-1 dBFS (0.891 linear).
const double kMpvLimitCeiling = 0.891;

/// Extra lift for Night Mode, approximating the +4 dB the native engine gets
/// from its own DynamicsProcessing stage.
const double kMpvNightMultiplier = 1.6;

/// The mpv `volume` property for a [baseFraction] system volume (0..1) with
/// [boost] and [nightMode] applied.
double mpvVolumePercent({
  required double baseFraction,
  required double boost,
  required bool nightMode,
}) {
  var vol = baseFraction * 100.0;
  if (boost > 1.01) vol *= boost;
  if (nightMode) vol *= kMpvNightMultiplier;
  if (vol < 0) vol = 0;
  return vol > kMpvVolumeMax ? kMpvVolumeMax : vol;
}

/// The limiter-only `af` chain for MPV, or null when no boost is wanted.
///
/// Deliberately carries NO gain: the gain is in [mpvVolumePercent]. So this
/// string is CONSTANT while boost is on, which means the volume gesture does
/// not rebuild mpv's filter graph on every frame — only when crossing the
/// boost threshold. Attaching a limiter that silently fails is still right:
/// without it the boost clips.
String? mpvBoostFilter(double boost, {required bool nightMode}) {
  final gain = nightMode ? boost * kMpvNightMultiplier : boost;
  if (gain <= 1.01) return null;
  // The graph MUST be single-quoted. `af` is an mpv *object settings list*
  // option, so mpv tokenises the value on commas — an unquoted graph is split
  // into two invalid list items and the whole chain fails to build. mpv's
  // manual is explicit: "Don't forget to quote libavfilter graphs".
  return "lavfi='[alimiter=level_in=1:level_out=1:"
      "limit=$kMpvLimitCeiling:attack=5:release=50]'";
}

/// The two values a volume gesture has to push: the system volume and the
/// engine make-up.
///
/// They are deliberately separate because the OS volume is capped at 100%
/// while the boost is not, so the gesture's single 0-200% value has to be
/// split rather than multiplied. Splitting (not multiplying) is also what
/// makes "swipe to 100%, keep going for boost" behave: below 100% you are
/// changing the system volume, above it the system volume simply stays pinned
/// at max and the extra travel becomes boost.
class VolumeSplit {
  const VolumeSplit(this.system, this.boost);

  /// 0..1, pushed to the OS so the system volume UI tracks the gesture.
  final double system;

  /// 1.0..[kMaxVolumeBoost], pushed to the engine as make-up gain.
  final double boost;

  @override
  bool operator ==(Object other) =>
      other is VolumeSplit && other.system == system && other.boost == boost;

  @override
  int get hashCode => Object.hash(system, boost);

  @override
  String toString() => 'VolumeSplit(system: ${system.toStringAsFixed(3)}, '
      'boost: ${boost.toStringAsFixed(3)})';
}

/// Splits a gesture value in 0..[volumeCeiling] into system volume + boost.
///
/// When [boostEnabled] is false the gesture is clamped to 100% and the boost
/// is pinned at 1.0, so switching the setting off restores the stock volume
/// behaviour exactly.
VolumeSplit splitVolume(double level, {required bool boostEnabled}) {
  if (!boostEnabled) {
    return VolumeSplit(level.clamp(0.0, kMaxVolumeNoBoost), 1.0);
  }
  if (level <= kMaxVolumeNoBoost) {
    return VolumeSplit(level.clamp(0.0, kMaxVolumeNoBoost), 1.0);
  }
  // Above 100% the system volume is already at max; the rest is boost.
  return VolumeSplit(kMaxVolumeNoBoost, level.clamp(1.0, kMaxVolumeBoost));
}

/// Gesture ceiling: 200% with boost on, 100% with it off.
double volumeCeiling({required bool boostEnabled}) =>
    boostEnabled ? kMaxVolumeBoost : kMaxVolumeNoBoost;