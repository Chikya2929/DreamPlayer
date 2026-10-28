import 'package:flutter_test/flutter_test.dart';

import 'package:dream_player/services/anime4k_shader_store.dart';
import 'package:dream_player/utils/thermal_policy.dart';

void main() {
  test('the headroom bands map to the tiers', () {
    expect(thermalTierFor(-1), ThermalTier.normal, reason: 'no reading');
    expect(thermalTierFor(0.0), ThermalTier.critical);
    expect(thermalTierFor(0.39), ThermalTier.critical);
    expect(thermalTierFor(0.40), ThermalTier.hot);
    expect(thermalTierFor(0.59), ThermalTier.hot);
    expect(thermalTierFor(0.60), ThermalTier.mild);
    expect(thermalTierFor(0.79), ThermalTier.mild);
    expect(thermalTierFor(0.80), ThermalTier.normal);
    expect(thermalTierFor(1.0), ThermalTier.normal);
  });

  test('a hotter tier never allows more than a cooler one', () {
    final order = [
      ThermalTier.normal,
      ThermalTier.mild,
      ThermalTier.hot,
      ThermalTier.critical,
    ];
    for (var i = 1; i < order.length; i++) {
      final cooler = thermalLimitFor(order[i - 1]);
      final hotter = thermalLimitFor(order[i]);
      expect(
        hotter.maxInterpolationFps,
        lessThanOrEqualTo(cooler.maxInterpolationFps),
        reason: '${order[i].name} allows more fps than ${order[i - 1].name}',
      );
      if (!cooler.allowAnime4k) {
        expect(hotter.allowAnime4k, isFalse);
      }
    }
  });

  test('the critical tier switches the GPU extras off', () {
    final limit = thermalLimitFor(ThermalTier.critical);
    expect(limit.maxInterpolationFps, 0);
    expect(limit.allowAnime4k, isFalse);
  });

  test('the hot tier only caps the interpolation', () {
    final limit = thermalLimitFor(ThermalTier.hot);
    expect(limit.maxInterpolationFps, 48);
    expect(limit.allowAnime4k, isTrue);
  });

  test('the Anime4K ladder steps down and stops at the cheapest mode', () {
    expect(stepDownAnime4k(Anime4kMode.ca), Anime4kMode.aa);
    expect(stepDownAnime4k(Anime4kMode.bb), Anime4kMode.aa);
    expect(stepDownAnime4k(Anime4kMode.aa), Anime4kMode.a);
    expect(stepDownAnime4k(Anime4kMode.c), Anime4kMode.b);
    expect(stepDownAnime4k(Anime4kMode.b), Anime4kMode.a);
    expect(stepDownAnime4k(Anime4kMode.a), Anime4kMode.a);
  });

  test('only the hot tier touches the Anime4K preset', () {
    expect(anime4kModeForTier(ThermalTier.normal, Anime4kMode.ca), isNull);
    expect(anime4kModeForTier(ThermalTier.mild, Anime4kMode.ca), isNull);
    expect(anime4kModeForTier(ThermalTier.critical, Anime4kMode.ca), isNull);
    expect(
      anime4kModeForTier(ThermalTier.hot, Anime4kMode.ca),
      Anime4kMode.aa,
    );
    // Already the cheapest mode: nothing to step down to.
    expect(anime4kModeForTier(ThermalTier.hot, Anime4kMode.a), isNull);
  });
}
