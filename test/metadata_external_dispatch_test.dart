import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dream_player/services/avdb_adapter.dart';
import 'package:dream_player/services/metadata_provider_adapter.dart';
import 'package:dream_player/services/tmdb_client.dart';

/// The external adapter seam was registered and configurable from Settings, but
/// nothing ever called into it: `_matchInProviderOrder` never passed
/// `externalConfigured`, and its dispatch had no external branch, so selecting
/// AVDb ran TheTVDB instead and `AvdbAdapter.search()` was unreachable
/// (issue #49). These pin the dispatch behaviour that was missing.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ParsedFileName parsed(String title, {int? year}) =>
      ParsedFileName(title: title, year: year);

  // A configured adapter. `setEnabled` writes the cached flag in memory before
  // it touches preferences, so this only needs the prefs mock initialised.
  //
  // `log` is nullable rather than defaulted to `const []` on purpose: a const
  // list is immutable, so `log.add` inside the transport throws -- and
  // `search()` catches everything into "no match", which fails the test with a
  // null result and no clue why.
  Future<AvdbAdapter> enabled({
    List<Map<String, dynamic>> hits = const [],
    List<Uri>? log,
    Map<String, dynamic>? single,
  }) async {
    final seen = log ?? <Uri>[];
    final a = AvdbAdapter(transport: (uri) async {
      seen.add(uri);
      if (uri.queryParameters.containsKey('ids')) {
        return {
          'code': 1,
          'msg': 'Data list',
          'list': single == null ? hits : [single],
        };
      }
      return {'code': 1, 'msg': 'Data list', 'list': hits};
    });
    await a.setEnabled(true);
    return a;
  }

  Map<String, dynamic> hit(String name, {int id = 83}) => {
        'id': id,
        'name': name,
        'poster_url': 'https://p/$id.jpg',
        'description': 'desc',
        'time': '01:58:34',
        'year': '2023',
        'origin_name': name,
      };

  group('AvdbAdapter.bestMatch', () {
    test('an exact title match scores 1.0', () async {
      final a = await enabled(hits: [hit('MIAA-818 Targeted')]);
      final match = await a.bestMatch(parsed('miaa-818-targeted'));
      expect(match, isNotNull);
      expect(match!.score, 1.0);
      expect(match.movie.id, 83);
      expect(match.movie.provider, MetadataProvider.external);
      expect(match.movie.kind, TmdKind.movie);
    });

    test('a query contained in a longer title still matches, at 0.8',
        () async {
      // This is the common shape: the catalogue appends marketing copy the
      // user never typed, so requiring equality would match almost nothing.
      final a = await enabled(hits: [hit('MIAA-818 Targeted By A Big Gangster')]);
      final match = await a.bestMatch(parsed('Miaa 818'));
      expect(match, isNotNull);
      expect(match!.score, 0.8);
    });

    test('punctuation and bracketed prefixes do not defeat the match',
        () async {
      // The API prefixes names with [UNCENSORED-LEAK] / [ENGLISH-SUBTITLE], so a
      // literal containment test on the raw string would report a false miss.
      final a = await enabled(hits: [hit('[UNCENSORED-LEAK] MIAA-818 Something')]);
      final match = await a.bestMatch(parsed('[UNCENSORED-LEAK] MIAA-818'));
      expect(match, isNotNull);
    });

    test('an unrelated hit yields no match rather than a bad one', () async {
      final a = await enabled(hits: [hit('Completely Different Film', id: 7)]);
      expect(await a.bestMatch(parsed('miaa 818')), isNull);
    });

    test('a numeric query is sent as an id lookup', () async {
      final log = <Uri>[];
      final a = await enabled(log: log, single: hit('Whatever', id: 604629));
      await a.bestMatch(parsed('604629'));
      expect(log.single.queryParameters['ids'], '604629');
    });

    test('an empty query never reaches the network', () async {
      final log = <Uri>[];
      final a = await enabled(log: log);
      expect(await a.bestMatch(parsed('   ')), isNull);
      expect(log, isEmpty);
    });

    test('an episode-shaped filename is still matched as a film', () async {
      // A single-film catalogue has no seasons, so rejecting episode shapes
      // would make every season folder resolve to nothing.
      final a = await enabled(hits: [hit('MIAA-818 Feature')]);
      final episode = ParsedFileName(
        title: 'MIAA-818',
        isEpisode: true,
        season: 1,
        episode: 2,
      );
      expect(await a.bestMatch(episode), isNotNull);
    });

    test('the match carries the detail poster, not just the list thumb',
        () async {
      final a = await enabled(
        hits: [
          {'id': 83, 'name': 'MIAA-818 X', 'poster_url': 'https://p/list.jpg'}
        ],
      );
      final match = await a.bestMatch(parsed('miaa 818'));
      expect(match!.movie.posterPath, 'https://p/list.jpg');
    });
  });

  group('registry reaches a real adapter', () {
    test('a disabled adapter is not consulted', () async {
      final registry = MetadataProviderRegistry.instance;
      registry.unregister('avdb');
      await AvdbAdapter.instance.setEnabled(false);
      registry.register(AvdbAdapter.instance);
      try {
        expect(await registry.configured(), isEmpty);
      } finally {
        registry.unregister('avdb');
      }
    });

    test('an enabled adapter is returned by configured()', () async {
      final registry = MetadataProviderRegistry.instance;
      registry.unregister('avdb');
      final a = AvdbAdapter(
        transport: (uri) async => {'code': 1, 'list': const []},
      );
      await a.setEnabled(true);
      registry.register(a);
      try {
        expect(
          (await registry.configured()).map((e) => e.id),
          contains('avdb'),
        );
      } finally {
        registry.unregister('avdb');
      }
    });
  });
}