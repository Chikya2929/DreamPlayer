import 'package:dream_player/l10n/app_localizations.dart';
import 'package:dream_player/services/layout_store.dart';
import 'package:dream_player/widgets/episode_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Issue #47: rows with no episode still rendered a bare movie icon even when
/// the show had a perfectly good poster.
///
/// The reported case was a movie-part folder: `Strike the Blood Final 01-04` is
/// four movies, and "Strike the Blood Final" has no TheTVDB record at all, so
/// there is no episode and therefore no per-episode still. The still pipeline
/// itself is healthy - TheTVDB serves per-episode stills for ~100% of episodes
/// on established shows, and `mapEpisodeResponse` already maps them - so what
/// was missing was the fallback when there is nothing to fall back FROM.
///
/// These tests pin the whole ladder: still wins, poster is the fallback, and
/// the icon appears only when there is genuinely no artwork.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const still = 'https://artworks.thetvdb.com/banners/episodes/1.jpg';
  const poster = 'https://artworks.thetvdb.com/banners/series/1.jpg';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(
    WidgetTester tester, {
    String? stillUrl,
    String? posterUrl,
    Widget Function(EpisodeThumbSize size)? thumbBuilder,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await LayoutStore.instance.setThumbSize(EpisodeThumbSize.medium);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: [
              EpisodeRow(
                stillUrl: stillUrl,
                posterUrl: posterUrl,
                thumbBuilder: thumbBuilder,
                title: const Text('Strike the Blood Final 01'),
                subtitle: const Text('1010 MB'),
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The still box is wide-and-short (112x63 at medium), the poster box
  /// tall-and-narrow (72x108), so the rendered size alone says which thumbnail
  /// the row picked.
  ///
  /// Read from LayoutStore per test, never cached: the store is seeded inside
  /// [pump], so a value captured earlier is the previous test's size.
  Size thumbBox(WidgetTester tester) =>
      tester.getSize(find.byKey(kEpisodeThumbBoxKey).first);

  testWidgets('a still wins over the poster when both are known', (tester) async {
    await pump(tester, stillUrl: still, posterUrl: poster);
    final box = thumbBox(tester);
    expect(box.width, moreOrLessEquals(LayoutStore.instance.thumbSize.still.w, epsilon: 0.5));
    expect(box.height, moreOrLessEquals(LayoutStore.instance.thumbSize.still.h, epsilon: 0.5));
  });

  testWidgets('no still falls back to the poster, not the bare icon', (tester) async {
    await pump(tester, posterUrl: poster);
    final box = thumbBox(tester);
    expect(box.width, moreOrLessEquals(LayoutStore.instance.thumbSize.poster.w, epsilon: 0.5));
    expect(box.height, moreOrLessEquals(LayoutStore.instance.thumbSize.poster.h, epsilon: 0.5));
    expect(find.byIcon(Icons.movie_outlined), findsNothing);
  });

  testWidgets('neither still nor poster keeps the placeholder icon', (tester) async {
    await pump(tester);
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(thumbBox(tester).height, moreOrLessEquals(LayoutStore.instance.thumbSize.still.h, epsilon: 0.5));
  });

  testWidgets('an explicit thumbBuilder still wins over the row defaults', (tester) async {
    await pump(
      tester,
      stillUrl: still,
      posterUrl: poster,
      thumbBuilder: (s) => EpisodePosterThumb(posterUrl: 'p', size: s),
    );
    // The custom builder produced the tall poster box even though a still
    // existed, so callers needing a different shape keep full control.
    expect(
      thumbBox(tester).height,
      moreOrLessEquals(LayoutStore.instance.thumbSize.poster.h, epsilon: 0.5),
    );
  });
}