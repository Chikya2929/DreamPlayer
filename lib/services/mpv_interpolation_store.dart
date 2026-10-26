import 'package:shared_preferences/shared_preferences.dart';

import '../utils/mpv_interpolation.dart';

/// Persists the libmpv frame-interpolation choice (issue #53).
class MpvInterpolationStore {
  MpvInterpolationStore._();

  static const String _fpsKey = 'dreamplayer.mpvInterpolationFps';
  static const String _filterKey = 'dreamplayer.mpvInterpolationFilter';

  /// The frame rates the UI offers. 0 is "off".
  static const List<int> targetFpsChoices = [0, 30, 48, 60, 120];

  static Future<MpvInterpolationConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final fps = prefs.getInt(_fpsKey) ?? 0;
    final filter = MpvInterpolationFilter.values.firstWhere(
      (f) => f.mpvName == prefs.getString(_filterKey),
      orElse: () => MpvInterpolationFilter.oversample,
    );
    return MpvInterpolationConfig(targetFps: fps, filter: filter);
  }

  static Future<void> save(MpvInterpolationConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_fpsKey, config.targetFps);
    await prefs.setString(_filterKey, config.filter.mpvName);
  }
}
