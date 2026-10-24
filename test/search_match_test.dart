import 'package:dream_player/utils/search_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeForSearch', () {
    test('lowercases and collapses punctuation to spaces', () {
      expect(normalizeForSearch('Dark.S01E05 [1080p]'), 'dark s01e05 1080p');
      expect(normalizeForSearch('  Amélie  '), 'amelie');
      expect(
        normalizeForSearch('Spider-Man: No Way Home'),
        'spider man no way home',
      );
    });

    test('folds accented latin letters so unaccented typing matches', () {
      expect(normalizeForSearch('Pokémon'), 'pokemon');
      expect(normalizeForSearch('Amélie'), 'amelie');
      expect(normalizeForSearch('Øresund'), 'oresund');
      expect(normalizeForSearch('Straße'), 'strasse');
    });
  });

  group('searchMatches', () {
    test('all query tokens must appear somewhere in the fields', () {
      expect(searchMatches('dark s01', ['Dark', 'S01E05']), isTrue);
      expect(searchMatches('dark x05', ['Dark', 'S01E05']), isFalse);
      expect(searchMatches('dark', ['Dark', 'S01E05']), isTrue);
    });

    test('an empty query matches everything (the screen shows no rows)', () {
      expect(searchMatches('', ['anything']), isTrue);
      expect(searchMatches('   ', ['anything']), isTrue);
    });

    test('punctuation and case in the query do not matter', () {
      expect(searchMatches('SPIDER-MAN', ['Spider Man']), isTrue);
      expect(searchMatches('spider man', ['Spider-Man']), isTrue);
    });

    test('an empty field set never matches a non-empty query', () {
      expect(searchMatches('dark', [null, '', '  ']), isFalse);
    });
  });

  group('searchRank', () {
    test('prefix beats contains beats secondary-only', () {
      expect(searchRank('dark', primary: 'Dark Season 1'), 0);
      expect(searchRank('season 1', primary: 'Dark Season 1'), 1);
      expect(searchRank('s01e05', primary: 'Dark', secondary: ['x S01E05']), 2);
    });

    test('returns null when nothing matches', () {
      expect(searchRank('nope', primary: 'Dark'), isNull);
    });

    test('normalizes before ranking, so accents do not demote', () {
      expect(searchRank('amelie', primary: 'Amélie'), 0);
    });
  });
}
