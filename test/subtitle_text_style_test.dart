import 'package:dream_player/services/subtitle_style.dart';
import 'package:dream_player/utils/subtitle_text_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('subtitleTextStyle', () {
    test('applies size, color and opacity', () {
      const style = SubtitleStyle(
        colorValue: 0xFFFFEB3B,
        textOpacity: 128,
      );
      final text = subtitleTextStyle(style, fontSize: 24);
      expect(text.fontSize, 24);
      expect(text.color, const Color(0x80FFEB3B));
      expect(text.height, 1.4);
    });

    test('background only when the box is enabled', () {
      const on = SubtitleStyle(
        backgroundColorValue: 0xFF1A237E,
        backgroundOpacity: 64,
      );
      expect(
        subtitleTextStyle(on, fontSize: 16).backgroundColor,
        const Color(0x401A237E),
      );
      const off = SubtitleStyle(backgroundColorValue: 0x00000000);
      expect(subtitleTextStyle(off, fontSize: 16).backgroundColor, isNull);
    });

    test('edge styles produce the expected shadows', () {
      expect(subtitleShadows(SubtitleEdge.none), isNull);
      expect(subtitleShadows(SubtitleEdge.outline), hasLength(4));
      expect(subtitleShadows(SubtitleEdge.dropShadow), hasLength(1));
      expect(subtitleShadows(SubtitleEdge.raised), hasLength(2));
      expect(subtitleShadows(SubtitleEdge.depressed), hasLength(2));
    });

    test('font families map to platform family names', () {
      expect(subtitleFontFamily(SubtitleFont.system), isNull);
      expect(subtitleFontFamily(SubtitleFont.sansSerif), 'sans-serif');
      expect(subtitleFontFamily(SubtitleFont.serif), 'serif');
      expect(subtitleFontFamily(SubtitleFont.monospace), 'monospace');
      expect(subtitleFontFamily(SubtitleFont.casual), 'casual');
      expect(subtitleFontFamily(SubtitleFont.cursive), 'cursive');
    });

    test('preview helper reflects the chosen family and edge', () {
      const style = SubtitleStyle(
        font: SubtitleFont.serif,
        edge: SubtitleEdge.dropShadow,
      );
      final text = subtitleTextStyle(style, fontSize: 12);
      expect(text.fontFamily, 'serif');
      expect(text.shadows, hasLength(1));
    });
  });
}
