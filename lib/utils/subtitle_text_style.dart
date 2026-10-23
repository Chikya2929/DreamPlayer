import 'package:flutter/material.dart';

import '../services/subtitle_style.dart';

/// Resolves a caption font family. `null` keeps the platform default, which is
/// what the "Default" option means on all three renderers.
String? subtitleFontFamily(SubtitleFont font) => switch (font) {
      SubtitleFont.system => null,
      SubtitleFont.sansSerif => 'sans-serif',
      SubtitleFont.serif => 'serif',
      SubtitleFont.monospace => 'monospace',
      SubtitleFont.casual => 'casual',
      SubtitleFont.cursive => 'cursive',
    };

/// Flutter stand-ins for the native edge treatments. Media3 and AVFoundation
/// draw a real glyph stroke for `outline`; Flutter has no stroke on `Text`, so
/// it is faked with four offset shadows (this helper is used by the settings
/// preview and the MPV text overlay only).
List<Shadow>? subtitleShadows(SubtitleEdge edge) => switch (edge) {
      SubtitleEdge.none => null,
      SubtitleEdge.outline => const [
          Shadow(color: Colors.black, offset: Offset(-1.2, 0)),
          Shadow(color: Colors.black, offset: Offset(1.2, 0)),
          Shadow(color: Colors.black, offset: Offset(0, -1.2)),
          Shadow(color: Colors.black, offset: Offset(0, 1.2)),
        ],
      SubtitleEdge.dropShadow => const [
          Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(2, 2)),
        ],
      SubtitleEdge.raised => const [
          Shadow(color: Colors.black87, blurRadius: 1, offset: Offset(2, 2)),
          Shadow(color: Colors.white70, blurRadius: 1, offset: Offset(-1, -1)),
        ],
      SubtitleEdge.depressed => const [
          Shadow(color: Colors.black87, blurRadius: 1, offset: Offset(-2, -2)),
          Shadow(color: Colors.white54, blurRadius: 1, offset: Offset(1, 1)),
        ],
    };

/// The one TextStyle builder shared by the settings preview and the MPV
/// subtitle overlay, so what the preview shows is what MPV draws.
TextStyle subtitleTextStyle(
  SubtitleStyle style, {
  required double fontSize,
  double height = 1.4,
  FontWeight fontWeight = FontWeight.w500,
}) =>
    TextStyle(
      color: style.effectiveTextColorValue,
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      fontFamily: subtitleFontFamily(style.font),
      backgroundColor:
          style.hasBackground ? style.effectiveBackgroundColorValue : null,
      shadows: subtitleShadows(style.edge),
    );
