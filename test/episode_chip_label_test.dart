import 'package:dream_player/utils/episode_label.dart';
import 'package:flutter_test/flutter_test.dart';

/// The player's file chip: `S01E05 · Episode name`.
///
/// The title line above it shows the SHOW title, so without this the episode
/// being played is anonymous. Everything here is pure label resolution — no
/// metadata store, no network — which is what makes it testable off-device.
void main() {
  group('fileEpisodeChipLabel', () {
    test('code + episode name for an SxxEyy file', () {
      expect(
        fileEpisodeChipLabel(
          title: 'Dark.S01E05.1080p.mkv',
          nameOf: (season, episode) =>
              season == 1 && episode == 5 ? 'Tarnished Cities' : null,
        ),
        'S01E05 · Tarnished Cities',
      );
    });

    test('code alone when TMDB has not named the episode', () {
      expect(
        fileEpisodeChipLabel(
          title: 'Dark.S01E05.mkv',
          nameOf: (season, episode) => null,
        ),
        'S01E05',
      );
    });

    test('blank / whitespace names do not produce a dangling separator', () {
      expect(
        fileEpisodeChipLabel(
          title: 'Dark.S01E05.mkv',
          nameOf: (season, episode) => '   ',
        ),
        'S01E05',
      );
    });

    test('structured season/episode (Jellyfin) beats the file name', () {
      // A Jellyfin item is titled with the episode NAME, so it carries no
      // SxxEyy at all; the numbers come from the server fields.
      expect(
        fileEpisodeChipLabel(
          title: 'Pilot',
          seasonNumber: 2,
          episodeNumber: 5,
          nameOf: (_, _) => 'Pilot',
        ),
        'S02E05 · Pilot',
      );
    });

    test('structured numbers win over a conflicting file name', () {
      expect(
        fileEpisodeChipLabel(
          title: 'Show.S01E05.mkv',
          seasonNumber: 2,
          episodeNumber: 5,
        ),
        'S02E05',
      );
    });

    test('anime [01] numbering uses the folder season', () {
      // `[VCB-Studio] Show [01] ...` has an episode but no season tag; the
      // folder's TMDB season match supplies it.
      expect(
        fileEpisodeChipLabel(
          title: '[SubsPlease] Show [01] [1080p].mkv',
          folderSeason: 4,
          nameOf: (season, episode) =>
              season == 4 && episode == 1 ? 'The Opening' : null,
        ),
        'S04E01 · The Opening',
      );
    });

    test('falls back to the first cached season when no folder season', () {
      expect(
        fileEpisodeChipLabel(
          title: 'Show [01] [1080p].mkv',
          firstAvailableSeason: 3,
        ),
        'S03E01',
      );
    });

    test('never invents a season for an episode-only name', () {
      // `seasonWithFallback` would default to 1 here — which mislabels a
      // season-4 file. No chip is the honest answer.
      expect(
        fileEpisodeChipLabel(title: 'Show [01] [1080p].mkv'),
        isNull,
      );
      expect(
        fileEpisodeChipLabel(title: 'Show [01] [1080p].mkv', folderSeason: 0),
        isNull,
      );
    });

    test('movies have no chip', () {
      expect(
        fileEpisodeChipLabel(title: 'Cocktail 2 (2025).mkv'),
        isNull,
      );
    });

    test('a truncated / unreadable name has no chip', () {
      expect(fileEpisodeChipLabel(title: ''), isNull);
    });
  });
}
