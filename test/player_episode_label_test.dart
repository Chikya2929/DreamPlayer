import 'package:dream_player/utils/episode_label.dart';
import 'package:flutter_test/flutter_test.dart';

/// `resolvedPlayerEpisode` decides which season/episode the player prints
/// beside the show title. Two rules to protect: structured server numbers win
/// over the name, and a season is never invented.
void main() {
  group('resolvedPlayerEpisode', () {
    test('reads S01E05 from the file name', () {
      final ep = resolvedPlayerEpisode(title: 'Dark.S01E05.mkv');
      expect(ep, isNotNull);
      expect(ep!.season, 1);
      expect(ep.episode, 5);
    });

    test('structured numbers win over a name without a code (Jellyfin)', () {
      final ep = resolvedPlayerEpisode(
        title: 'Tarnished Cities',
        seasonNumber: 2,
        episodeNumber: 7,
      );
      expect(ep!.season, 2);
      expect(ep.episode, 7);
    });

    test('structured numbers win over a conflicting file name', () {
      final ep = resolvedPlayerEpisode(
        title: 'Show.S01E01.mkv',
        seasonNumber: 3,
        episodeNumber: 9,
      );
      expect(ep!.season, 3);
      expect(ep.episode, 9);
    });

    test('an anime [01] name takes the folder season', () {
      final ep = resolvedPlayerEpisode(
        title: 'Show [01] [1080p].mkv',
        folderSeason: 2,
      );
      expect(ep!.season, 2);
      expect(ep.episode, 1);
    });

    test('an episode-only name falls back to the first cached season', () {
      final ep = resolvedPlayerEpisode(
        title: 'Show E05.mkv',
        firstAvailableSeason: 4,
      );
      expect(ep!.season, 4);
      expect(ep.episode, 5);
    });

    test('an episode-only name never invents a season', () {
      expect(resolvedPlayerEpisode(title: 'Show E05.mkv'), isNull);
      expect(
        resolvedPlayerEpisode(title: 'Show E05.mkv', folderSeason: 0),
        isNull,
      );
      expect(
        resolvedPlayerEpisode(title: 'Show [01] [1080p].mkv'),
        isNull,
      );
    });

    test('season 0 is not a usable fallback (specials are not a label)', () {
      expect(
        resolvedPlayerEpisode(title: 'Show E05.mkv', firstAvailableSeason: 0),
        isNull,
      );
    });

    test('a movie has no episode line', () {
      expect(resolvedPlayerEpisode(title: 'Cocktail 2 (2025).mkv'), isNull);
    });

    test('an empty title yields nothing', () {
      expect(resolvedPlayerEpisode(title: ''), isNull);
    });
  });
}
