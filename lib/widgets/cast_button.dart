import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// View type registered in `MainActivity.kt` (`CastButtonViewFactory`).
const String castButtonViewType = 'dreamplayer/cast_button';

/// The Google Cast route picker, embedded as a platform view.
///
/// Android only. The Cast SDK 22.x no longer ships its own button widget,
/// so the native side hosts the AndroidX `MediaRouteButton` and lets the
/// SDK install its route selector via `CastButtonFactory` — the documented
/// integration path. The native view hides itself while no Cast route
/// exists on the network, so the player chrome does not grow an inert icon
/// on a device with nothing to cast to.
class CastButton extends StatelessWidget {
  const CastButton({super.key, this.size = 40});

  /// False on iOS, desktop and in widget tests, where the platform view
  /// type does not exist — building an [AndroidView] there would hang on a
  /// platform-view creation that never answers.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  final double size;

  @override
  Widget build(BuildContext context) {
    if (!isSupported) return const SizedBox.shrink();
    return SizedBox(
      width: size,
      height: size,
      child: AndroidView(
        viewType: castButtonViewType,
        creationParams: const <String, dynamic>{},
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}
