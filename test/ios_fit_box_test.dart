import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dream_player/services/exo_player.dart';

void main() {
  void expectSize(Size actual, double width, double height) {
    expect(actual.width, closeTo(width, 0.01));
    expect(actual.height, closeTo(height, 0.01));
  }

  test('non-fixed modes fill the available space', () {
    const available = Size(1000, 500);
    for (final mode in [
      VideoFitMode.fit,
      VideoFitMode.fullscreen,
      VideoFitMode.crop,
      VideoFitMode.stretch,
    ]) {
      expect(iosFitBoxSize(available, mode), available);
    }
  });

  test('landscape screen boxes a 16:9 mode by height', () {
    expectSize(
      iosFitBoxSize(const Size(1000, 400), VideoFitMode.ratio16x9),
      711.11,
      400,
    );
  });

  test('wide screen boxes a 16:9 mode by width', () {
    expectSize(
      iosFitBoxSize(const Size(1000, 800), VideoFitMode.ratio16x9),
      1000,
      562.5,
    );
  });

  test('portrait screen boxes a 4:3 mode by width', () {
    expectSize(
      iosFitBoxSize(const Size(400, 1000), VideoFitMode.ratio4x3),
      400,
      300,
    );
  });

  test('each fixed ratio is honoured', () {
    const available = Size(1000, 500);
    expectSize(iosFitBoxSize(available, VideoFitMode.ratio185), 925, 500);
    expectSize(iosFitBoxSize(available, VideoFitMode.ratio239), 1000, 418.41);
  });

  test('degenerate and unbounded constraints do not produce NaN', () {
    expect(iosFitBoxSize(Size.zero, VideoFitMode.ratio16x9), Size.zero);
    expect(
      iosFitBoxSize(const Size(double.infinity, 500), VideoFitMode.ratio16x9),
      const Size(double.infinity, 500),
    );
  });
}
