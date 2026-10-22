import 'package:flutter/material.dart';

class FormatChip extends StatelessWidget {
  const FormatChip({
    super.key,
    required this.label,
    required this.color,
    this.maxWidth,
  });

  final String label;
  final Color color;

  /// Caps the chip's width and ellipsizes the label on one line.
  ///
  /// Unset by default: the format chips carry short fixed labels (`HEVC`,
  /// `5.1`, `SDR`) that never need truncating. The player's file chip is built
  /// from a free-form episode name, so it passes the available width here —
  /// without it a long name wraps the `Text` onto several lines and the chip
  /// grows taller than every chip beside it.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
        child: Text(
          label,
          maxLines: maxWidth == null ? null : 1,
          overflow: maxWidth == null ? null : TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
