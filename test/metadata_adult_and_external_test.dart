import 'package:dream_player/services/adult_content_store.dart';
import 'package:dream_player/services/metadata_provider_adapter.dart';
import 'package:dream_player/services/the_tvdb_client.dart';
import 'package:dream_player/services/tmdb_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Issue #46.
///
/// Part 1: adult metadata. TMDB is asked `include_adult=false` at the single
/// site that gates it, so an adult title resolves to no match. Measured live:
/// `query=hentai` returns 0 adult results with it false, 4 with it true.
///
/// Part 2: external metadata providers (e.g. AVDb). The seam is an adapter, and
/// the Settings contract is that selecting one shows ONLY its own field while
/// TheTVDB's fallback switch appears for it (not for TMDB, which is no longer
/// the resolver).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdultContentStore', () {
    test('defaults to off so existing installs keep current behaviour', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AdultContentStore();
      expect(await store.load(), isFalse);
      expect(store.includeAdult, isFalse);
    });

    test('persists the choice and reloads it', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AdultContentStore();
      await store.setIncludeAdult(true);
      expect(await store.load(), isTrue);

      // A fresh store instance must read the persisted value, not the default.
      final reloaded = AdultContentStore();
      expect(await reloaded.load(), isTrue);
    });

    test('turning it back off persists too', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AdultContentStore();
      await store.setIncludeAdult(true);
      await store.setIncludeAdult(false);
      expect(await AdultContentStore().load(), isFalse);
    });

    test('a broken preferences store falls back to off, not a crash', () async {
      final store = AdultContentStore(
        preferences: () async => throw StateError('prefs gone'),
      );
      expect(await store.load(), isFalse);
      // And the in-memory value still applies for the session.
      expect(await store.setIncludeAdult(true), isTrue);
    });
  });

  group('providerOrderFor - external (issue #46 part 2)', () {
    test('external becomes primary, with TMDB and TheTVDB behind it', () {
      final order = providerOrderFor(
        choice: MetadataProviderChoice.external,
        tmdbConfigured: true,
        theTvdbConfigured: true,
        theTvdbFallbackEnabled: true,
        externalConfigured: true,
      );
      expect(order.first, MetadataProvider.external);
      expect(order, contains(MetadataProvider.tmdb));
      expect(order, contains(MetadataProvider.theTvdb));
    });

    test('TheTVDB stays out unless its fallback switch is on', () {
      final order = providerOrderFor(
        choice: MetadataProviderChoice.external,
        tmdbConfigured: true,
        theTvdbConfigured: true,
        theTvdbFallbackEnabled: false,
        externalConfigured: true,
      );
      expect(order, isNot(contains(MetadataProvider.theTvdb)));
    });

    test('an unconfigured external choice falls back to the built-ins', () {
      // The Settings segment is hidden until an adapter registers, so this is
      // defence in depth: a choice that resolves nothing must not happen.
      final order = providerOrderFor(
        choice: MetadataProviderChoice.external,
        tmdbConfigured: true,
        theTvdbConfigured: false,
        theTvdbFallbackEnabled: true,
        externalConfigured: false,
      );
      expect(order, [MetadataProvider.tmdb]);
    });

    test('external with nothing else configured still yields TMDB', () {
      final order = providerOrderFor(
        choice: MetadataProviderChoice.external,
        tmdbConfigured: false,
        theTvdbConfigured: false,
        theTvdbFallbackEnabled: false,
        externalConfigured: false,
      );
      expect(order, [MetadataProvider.tmdb]);
    });

    test('the built-in orderings are unchanged by the new option', () {
      expect(
        providerOrderFor(
          choice: MetadataProviderChoice.tmdb,
          tmdbConfigured: true,
          theTvdbConfigured: true,
          theTvdbFallbackEnabled: true,
        ),
        [MetadataProvider.tmdb, MetadataProvider.theTvdb],
      );
      expect(
        providerOrderFor(
          choice: MetadataProviderChoice.theTvdb,
          tmdbConfigured: true,
          theTvdbConfigured: true,
          theTvdbFallbackEnabled: true,
        ),
        [MetadataProvider.theTvdb, MetadataProvider.tmdb],
      );
    });
  });

  group('providerChoice round-trip', () {
    test('external persists and reloads', () async {
      SharedPreferences.setMockInitialValues({});
      await TheTvdbClient.setProviderChoice(MetadataProviderChoice.external);
      expect(
        await TheTvdbClient.providerChoice(),
        MetadataProviderChoice.external,
      );
    });

    test('an unrecognised stored value falls back to TMDB', () async {
      // A cache written by a newer build must not crash deserialization.
      SharedPreferences.setMockInitialValues({
        TheTvdbClient.providerPrefsKey: 'someFutureProvider',
      });
      expect(await TheTvdbClient.providerChoice(), MetadataProviderChoice.tmdb);
    });
  });

  group('provider-qualified cache keys', () {
    test('external is a distinct provider and gets its own key', () {
      final movie = TmdMovie(
        id: 42,
        title: 'Anything',
        provider: MetadataProvider.external,
      );
      expect(movie.providerKey, 'external:movie:42');
      expect(
        movie.providerKey,
        isNot(TmdMovie(id: 42, title: 'x').providerKey),
        reason: 'an external id must not collide with the same TMDB id',
      );
    });

    test('provider names round-trip through the cache', () {
      for (final provider in MetadataProvider.values) {
        final movie = TmdMovie(id: 7, title: 'T', provider: provider);
        final decoded = TmdMovie.fromMetaJson(movie.toJson());
        expect(decoded.provider, provider, reason: provider.name);
      }
    });

    test('an unknown stored provider name decodes as TMDB', () {
      final decoded = TmdMovie.fromMetaJson({
        'id': 1,
        'title': 'T',
        'provider': 'somethingNewer',
      });
      expect(decoded.provider, MetadataProvider.tmdb);
    });
  });

  group('TMDB include_adult parameter (issue #46 part 1)', () {
    // The query string IS the switch: nothing else in the app filters adult
    // results, so this asserts the exact wire parameter rather than re-deriving
    // the behaviour from a live API call.
    Future<Uri> captureSearch({
      required bool? includeAdult,
      bool persisted = false,
    }) async {
      SharedPreferences.setMockInitialValues({
        if (persisted) includeAdultPrefsKey: true,
      });
      Uri? seen;
      final api = TmdApi(
        apiKey: 'test-key',
        transport: (uri) async {
          seen = uri;
          return const TmdTransportResponse(
            statusCode: 200,
            body: '{"results": []}',
          );
        },
      );
      await api.search('hentai', includeAdult: includeAdult);
      return seen!;
    }

    test('defaults to include_adult=false', () async {
      final uri = await captureSearch(includeAdult: null);
      expect(uri.queryParameters['include_adult'], 'false');
    });

    test('reads the persisted setting when no argument is passed', () async {
      final uri = await captureSearch(includeAdult: null, persisted: true);
      expect(uri.queryParameters['include_adult'], 'true');
    });

    test('an explicit true overrides the persisted default', () async {
      final uri = await captureSearch(includeAdult: true);
      expect(uri.queryParameters['include_adult'], 'true');
    });

    test('an explicit false overrides a persisted true', () async {
      final uri = await captureSearch(includeAdult: false, persisted: true);
      expect(uri.queryParameters['include_adult'], 'false');
    });

    test('the parameter is present on a TV search too', () async {
      Uri? seen;
      final api = TmdApi(
        apiKey: 'test-key',
        transport: (uri) async {
          seen = uri;
          return const TmdTransportResponse(
            statusCode: 200,
            body: '{"results": []}',
          );
        },
      );
      await api.search('some show', kind: TmdKind.tv, includeAdult: true);
      expect(seen!.path, contains('/search/tv'));
      expect(seen!.queryParameters['include_adult'], 'true');
    });
  });

  group('MetadataProviderRegistry', () {
    late MetadataProviderRegistry registry;

    setUp(() {
      registry = MetadataProviderRegistry.instance;
      registry.unregister('test-provider');
    });

    tearDown(() => registry.unregister('test-provider'));

    test('registers, finds and unregisters by id', () {
      final adapter = _FakeAdapter('test-provider');
      registry.register(adapter);
      expect(registry.adapters.map((a) => a.id), contains('test-provider'));
      expect(registry.byId('test-provider'), same(adapter));

      registry.unregister('test-provider');
      expect(registry.byId('test-provider'), isNull);
    });

    test('registering the same id twice keeps the first', () {
      registry.register(_FakeAdapter('test-provider'));
      registry.register(_FakeAdapter('test-provider'));
      expect(
        registry.adapters.where((a) => a.id == 'test-provider').length,
        1,
      );
    });

    test('configured() skips adapters with no credentials', () async {
      registry.register(_FakeAdapter('test-provider'));
      final configured = await registry.configured();
      expect(configured.where((a) => a.id == 'test-provider'), isEmpty);
    });

    test('configured() keeps adapters that report themselves configured', () async {
      registry.register(_FakeAdapter('test-provider', configured: true));
      final configured = await registry.configured();
      expect(configured.map((a) => a.id), contains('test-provider'));
    });

    test('an adapter that throws does not break the others', () async {
      registry.register(_FakeAdapter('test-provider', throwsOnConfigured: true));
      // Must not throw: one misbehaving adapter cannot block resolution.
      expect(await registry.configured(), isNotNull);
    });
  });
}

class _FakeAdapter extends MetadataProviderAdapter {
  _FakeAdapter(
    this.id, {
    this.configured = false,
    this.throwsOnConfigured = false,
  });

  @override
  final String id;

  final bool configured;
  final bool throwsOnConfigured;

  @override
  String get label => 'Test';

  @override
  Future<List<TmdMovie>> search(String query, {TmdKind kind = TmdKind.movie}) async =>
      const [];

  @override
  Future<TmdDetails?> details(TmdMovie movie) async => null;

  @override
  Future<List<TmdSeason>> seasons(TmdMovie movie) async => const [];

  @override
  Future<bool> isConfigured() async {
    if (throwsOnConfigured) throw StateError('boom');
    return configured;
  }
}