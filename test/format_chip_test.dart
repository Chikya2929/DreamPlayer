import 'package:dream_player/widgets/format_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `maxWidth` is what lets the player's file chip carry a free-form episode
/// name. Without it the `Text` wraps onto several lines and the chip grows
/// taller than every format chip beside it, which is what this pins.
void main() {
  const longLabel =
      'S01E05 · The Longest Episode Title Anyone Has Ever Written For Television';

  Widget host(Widget chip, {double width = 260}) => MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: SizedBox(width: width, child: chip)),
        ),
      );

  testWidgets('a capped label stays on one line', (tester) async {
    await tester.pumpWidget(host(
      const FormatChip(
        label: longLabel,
        color: Colors.white,
        maxWidth: 220,
      ),
    ));
    expect(tester.takeException(), isNull);
    // One 11 px line + 8 px vertical padding + 2 px border ≈ 24 px. A wrapped
    // second line pushes it past 30.
    expect(tester.getSize(find.byType(FormatChip)).height, lessThan(30));
  });

  testWidgets('the label is ellipsized, not clipped mid-glyph silently',
      (tester) async {
    await tester.pumpWidget(host(
      const FormatChip(
        label: longLabel,
        color: Colors.white,
        maxWidth: 120,
      ),
    ));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short chip is unchanged', (tester) async {
    await tester.pumpWidget(host(const FormatChip(
      label: 'HEVC',
      color: Colors.white,
    )));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.maxLines, isNull);
    expect(text.overflow, isNull);
    expect(tester.takeException(), isNull);
  });
}
