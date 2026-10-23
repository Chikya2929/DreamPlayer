import 'package:flutter/material.dart';

import '../services/subtitle_style.dart';
import '../utils/subtitle_text_style.dart';

/// Subtitle appearance, modelled on YouTube's caption options: font, size,
/// text color + opacity, background color + opacity, edge style, position and
/// cue delay. The preview box is rendered with the same
/// [subtitleTextStyle] helper the MPV overlay uses, so it matches what plays.
class SubtitleSettingsScreen extends StatefulWidget {
  const SubtitleSettingsScreen({super.key});

  @override
  State<SubtitleSettingsScreen> createState() => _SubtitleSettingsScreenState();
}

class _SubtitleSettingsScreenState extends State<SubtitleSettingsScreen> {
  SubtitleStyle _style = const SubtitleStyle();
  bool _loaded = false;

  static const _textColors = <int, String>{
    0xFFFFFFFF: 'White',
    0xFFFFEB3B: 'Yellow',
    0xFF69F0AE: 'Green',
    0xFF80DEEA: 'Cyan',
    0xFFFF80AB: 'Pink',
    0xFF82B1FF: 'Blue',
  };

  /// Background swatches. `0x00000000` is the explicit "none" choice; every
  /// other entry carries a full alpha and the opacity slider overrides it.
  static const _backgrounds = <int, String>{
    0x00000000: 'None',
    0xFF000000: 'Black',
    0xFFFFFFFF: 'White',
    0xFF1A237E: 'Navy',
    0xFF424242: 'Grey',
  };

  @override
  void initState() {
    super.initState();
    SubtitleStyle.load().then((style) {
      if (!mounted) return;
      setState(() {
        _style = style;
        _loaded = true;
      });
    });
  }

  Future<void> _update(SubtitleStyle style) async {
    setState(() => _style = style);
    await style.save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subtitles'),
        actions: [
          TextButton(
            onPressed: _loaded
                ? () => _update(const SubtitleStyle())
                : null,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _preview(theme),
                _section(theme, 'Font'),
                _dropdown<SubtitleFont>(
                  value: _style.font,
                  values: SubtitleFont.values,
                  label: (f) => f.label,
                  onChanged: (font) => _update(_style.copyWith(font: font)),
                ),
                _section(theme, 'Text size'),
                _slider(
                  title: '${(_style.sizeMultiplier * 100).round()}%',
                  value: _style.sizeMultiplier.clamp(0.5, 2.0),
                  min: 0.5,
                  max: 2.0,
                  divisions: 30,
                  label: '${(_style.sizeMultiplier * 100).round()}%',
                  onChanged: (v) => _update(
                    _style.copyWith(
                      sizeMultiplier: double.parse(v.toStringAsFixed(2)),
                    ),
                  ),
                ),
                _section(theme, 'Text color'),
                _swatches(
                  options: _textColors,
                  // Compare the RGB only: the stored color's alpha is the
                  // separate text-opacity slider, and the swatch options carry
                  // their own 0xFF alpha. Comparing full ARGB made the default
                  // white invisible as "selected" and no text color ever showed
                  // a check.
                  isSelected: (value) =>
                      (value & 0x00FFFFFF) ==
                      (_style.colorValue & 0x00FFFFFF),
                  onSelected: (value) =>
                      _update(_style.copyWith(colorValue: value | 0xFF000000)),
                ),
                _section(theme, 'Text opacity'),
                _slider(
                  title:
                      '${((_style.textOpacity / 255.0) * 100).round()}%',
                  value: _style.textOpacity / 255.0,
                  min: 0.0,
                  max: 1.0,
                  divisions: 100,
                  label:
                      '${((_style.textOpacity / 255.0) * 100).round()}%',
                  onChanged: (v) => _update(
                    _style.copyWith(textOpacity: (v * 255).round()),
                  ),
                ),
                _section(theme, 'Background'),
                _swatches(
                  options: _backgrounds,
                  isSelected: (value) => value == 0x00000000
                      ? !_style.hasBackground
                      : _style.hasBackground &&
                          value ==
                              (_style.backgroundColorValue & 0x00FFFFFF),
                  onSelected: (value) => _update(
                    _style.copyWith(backgroundColorValue: value),
                  ),
                ),
                if (_style.hasBackground) ...[
                  _section(theme, 'Background opacity'),
                  _slider(
                    title:
                        '${((_style.backgroundOpacity / 255.0) * 100).round()}%',
                    value: _style.backgroundOpacity / 255.0,
                    min: 0.0,
                    max: 1.0,
                    divisions: 100,
                    label:
                        '${((_style.backgroundOpacity / 255.0) * 100).round()}%',
                    onChanged: (v) => _update(
                      _style.copyWith(backgroundOpacity: (v * 255).round()),
                    ),
                  ),
                ],
                _section(theme, 'Edge style'),
                _dropdown<SubtitleEdge>(
                  value: _style.edge,
                  values: SubtitleEdge.values,
                  label: (e) => e.label,
                  onChanged: (edge) => _update(_style.copyWith(edge: edge)),
                ),
                _section(theme, 'Position'),
                _slider(
                  title: '${_style.verticalPosition}',
                  value: _style.verticalPosition.toDouble(),
                  min: SubtitleStyle.minVerticalPosition.toDouble(),
                  max: SubtitleStyle.maxVerticalPosition.toDouble(),
                  divisions: SubtitleStyle.maxVerticalPosition,
                  label: '${_style.verticalPosition}',
                  onChanged: (v) => _update(
                    _style.copyWith(verticalPosition: v.round()),
                  ),
                  hint: 'Move subtitle text up (higher) or down (lower).',
                ),
                _section(theme, 'Delay'),
                _slider(
                  title:
                      '${_style.delaySeconds > 0 ? '+' : ''}${_style.delaySeconds.toStringAsFixed(2)} s',
                  value: _style.delaySeconds.clamp(
                    SubtitleStyle.minDelayMs / 1000,
                    SubtitleStyle.maxDelayMs / 1000,
                  ),
                  min: SubtitleStyle.minDelayMs / 1000,
                  max: SubtitleStyle.maxDelayMs / 1000,
                  divisions: 240,
                  label:
                      '${_style.delaySeconds > 0 ? '+' : ''}${_style.delaySeconds.toStringAsFixed(2)} s',
                  onChanged: (seconds) => _update(
                    _style.copyWith(delayMs: (seconds * 1000).round()),
                  ),
                  hint: 'Positive values show subtitles later than authored — '
                      'use it to fix out-of-sync files.',
                ),
              ],
            ),
    );
  }

  Widget _preview(ThemeData theme) {
    final media = MediaQuery.of(context).size;
    final isLandscape = media.width > media.height;
    var boxH = media.width * 9 / 16;
    final maxH = media.height * (isLandscape ? 0.42 : 0.35);
    if (boxH > maxH) boxH = maxH;
    if (boxH < 120) boxH = 120;
    final boxW = boxH * 16 / 9;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Center(
        child: Container(
          width: boxW,
          height: boxH,
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.dividerColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF455A64),
                        Color(0xFF0D1B20),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    // Same mapping as the player: vPos 0 = bottom, 255 = top.
                    padding: EdgeInsets.only(
                      bottom: boxH * (_style.verticalPosition / 255.0),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Sample subtitle line',
                        textAlign: TextAlign.center,
                        // Same builder as the MPV overlay, so the preview is
                        // the renderer's own style rather than an imitation.
                        style: subtitleTextStyle(
                          _style,
                          fontSize: boxH * 0.0533 * _style.sizeMultiplier,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _swatches({
    required Map<int, String> options,
    required bool Function(int) isSelected,
    required ValueChanged<int> onSelected,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: options.entries.map((entry) {
          final selected = isSelected(entry.key);
          return Semantics(
            button: true,
            selected: selected,
            label: entry.value,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              focusColor:
                  theme.colorScheme.primary.withValues(alpha: 0.25),
              onTap: () => onSelected(entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: selected
                      ? theme.colorScheme.primary.withValues(alpha: 0.12)
                      : null,
                  border: Border.all(
                    width: selected ? 2.5 : 1,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.dividerColor,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _swatchDot(entry.key),
                    const SizedBox(width: 6),
                    Text(entry.value),
                    if (selected) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.check,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _swatchDot(int argb) {
    final color = Color(argb);
    final empty = argb == 0x00000000;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: empty ? Colors.transparent : color,
        border: Border.all(color: Colors.white54),
      ),
      child: empty
          ? const Icon(Icons.block, size: 12, color: Colors.white54)
          : null,
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<T> values,
    required String Function(T) label,
    required ValueChanged<T> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DropdownButtonFormField<T>(
          key: ValueKey(value),
          initialValue: value,
          isExpanded: true,
          items: values
              .map((v) => DropdownMenuItem<T>(value: v, child: Text(label(v))))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      );

  Widget _slider({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
    String? hint,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          Slider(
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            value: value,
            onChanged: onChanged,
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
        child: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
