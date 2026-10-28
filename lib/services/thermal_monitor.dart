import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:dream_player/utils/thermal_policy.dart';

/// Polls the device's thermal headroom while a video is playing.
///
/// Android publishes the reading (`PowerManager.getThermalHeadroom`, API 30+)
/// and nothing else: deciding what to do about it is our policy, and it lives
/// in `lib/utils/thermal_policy.dart` so it can be unit-tested without a
/// phone.
///
/// The monitor never *raises* the quality back on its own. A phone that heats
/// up and cools down again would otherwise flap between presets every ten
/// seconds, and the picture would keep changing under the viewer. The user's
/// own choice stays the ceiling; the monitor only lowers it.
class ThermalMonitor extends ChangeNotifier {
  ThermalMonitor._();

  static final ThermalMonitor instance = ThermalMonitor._();

  static const MethodChannel _channel = MethodChannel('dreamplayer/thermal');

  /// How often the reading is sampled.
  static const Duration pollInterval = Duration(seconds: 10);

  /// Test hook: `--dart-define=THERMAL_SIMULATE_TIER=hot` forces a tier so
  /// the downgrade path can be verified on a phone that is not actually hot.
  /// Unset in every real build (the release workflow passes no such define).
  static const String _simulateTier =
      String.fromEnvironment('THERMAL_SIMULATE_TIER');

  double _headroom = -1;
  ThermalTier _tier = ThermalTier.normal;
  Timer? _timer;
  bool _polling = false;

  /// The last reading, or -1 when the platform cannot tell us.
  double get headroom => _headroom;

  /// The tier the last reading falls into.
  ThermalTier get tier => _tier;

  /// True while the monitor is sampling.
  bool get isPolling => _polling;

  /// Starts sampling. Safe to call twice.
  void start() {
    if (_polling) return;
    _polling = true;
    unawaited(sample());
    _timer = Timer.periodic(pollInterval, (_) => unawaited(sample()));
  }

  /// Stops sampling.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _polling = false;
  }

  /// Takes one reading and publishes the new tier.
  ///
  /// Returns the new tier, so a caller can react without waiting for the
  /// notifier.
  Future<ThermalTier> sample() async {
    final simulated = _simulatedTier();
    if (simulated != null) {
      final changed = simulated != _tier;
      _headroom = 0.5;
      _tier = simulated;
      if (changed) notifyListeners();
      return _tier;
    }
    final reading = await readHeadroom();
    if (reading < 0) {
      // No reading (older Android, or the platform refused): leave the tier
      // alone rather than pretending the device is cool.
      return _tier;
    }
    final tier = thermalTierFor(reading);
    final changed = tier != _tier || reading != _headroom;
    _headroom = reading;
    _tier = tier;
    if (changed) notifyListeners();
    return tier;
  }

  /// The forced tier, when the build asks for one.
  static ThermalTier? _simulatedTier() {
    switch (_simulateTier) {
      case 'normal':
        return ThermalTier.normal;
      case 'mild':
        return ThermalTier.mild;
      case 'hot':
        return ThermalTier.hot;
      case 'critical':
        return ThermalTier.critical;
      default:
        return null;
    }
  }

  /// Reads the headroom once. Returns -1 when it is not available.
  static Future<double> readHeadroom() async {
    if (defaultTargetPlatform != TargetPlatform.android) return -1;
    try {
      final value = await _channel.invokeMethod<num>('getThermalHeadroom');
      if (value == null) return -1;
      return value.toDouble();
    } catch (e) {
      debugPrint('thermal: headroom read failed: $e');
      return -1;
    }
  }
}
