import 'package:flutter/foundation.dart';

import 'tmdb_client.dart';

/// A metadata source that is neither TMDB nor TheTVDB.
///
/// Added for issue #46, part 2 ("custom external metadata APIs", e.g.
/// avdbapi.com). TheTVDB was added as a second provider by teaching
/// `TmdMovie`/`MetadataProvider` about it; an *arbitrary* third-party service is
/// a different shape of problem, because each one has its own response schema.
///
/// So the seam is an adapter: the rest of the app keeps speaking
/// [TmdMovie]/[TmdDetails] and never learns where the data came from, while a
/// new source is written as one implementation of this interface. That is the
/// difference between adding a provider and making providers extensible.
///
/// Registered providers are consulted in registration order, after the built-in
/// ones, and only when [isConfigured] is true - an adapter with no credentials
/// is skipped rather than failing the whole resolution.
abstract class MetadataProviderAdapter {
  /// Stable identifier, persisted in the metadata cache's provider-qualified
  /// keys (`TmdMovie.providerKey` is `<provider>:<kind>:<id>`). Never reuse an
  /// existing provider's name.
  String get id;

  /// Human-readable name for Settings.
  String get label;

  /// Whether this provider has everything it needs to run. An unconfigured
  /// adapter is skipped silently.
  Future<bool> isConfigured();

  /// Currently saved API key, or null. Shown in Settings so the dialog can be
  /// pre-filled with the existing value.
  String? get currentApiKey => null;

  /// Persist [apiKey]; an empty string clears it.
  Future<void> saveApiKey(String apiKey) async {}

  /// One line under the field title in Settings, explaining where to get a key.
  String get credentialsHelp => 'Optional API key for this provider.';

  /// Search for a title. Returns candidates already shaped as [TmdMovie] with
  /// [provider] set to [MetadataProvider.external].
  ///
  /// Returning an empty list means "no confident match", never an error: the
  /// caller falls through to the next provider.
  Future<List<TmdMovie>> search(String query, {TmdKind kind = TmdKind.movie});

  /// Full detail for a [TmdMovie] previously returned by [search].
  Future<TmdDetails?> details(TmdMovie movie);

  /// Seasons and episodes. Optional: a provider that cannot supply them may
  /// return an empty list, and the season screen falls back to filename parsing.
  ///
  /// Defaulted (rather than abstract) so a single-film catalogue — AVDb, or any
  /// source with no notion of a season — is four methods, not six.
  Future<List<TmdSeason>> seasons(TmdMovie movie) async => const [];

  /// Per-episode detail, including stills and cast where available.
  Future<TmdEpisode?> episode(TmdMovie movie, int season, int episode) =>
      Future.value(null);
}

/// Registry of [MetadataProviderAdapter] implementations.
///
/// Kept deliberately small: a static list plus a notifier, because the set
/// changes at startup (after Settings loads credentials) rather than per frame.
class MetadataProviderRegistry {
  MetadataProviderRegistry._();

  static final MetadataProviderRegistry instance = MetadataProviderRegistry._();

  final List<MetadataProviderAdapter> _adapters = [];
  final List<VoidCallback> _listeners = [];

  /// Adapters in consultation order.
  List<MetadataProviderAdapter> get adapters => List.unmodifiable(_adapters);

  void register(MetadataProviderAdapter adapter) {
    if (_adapters.any((a) => a.id == adapter.id)) return;
    _adapters.add(adapter);
    _notify();
  }

  void unregister(String id) {
    _adapters.removeWhere((a) => a.id == id);
    _notify();
  }

  MetadataProviderAdapter? byId(String id) {
    for (final adapter in _adapters) {
      if (adapter.id == id) return adapter;
    }
    return null;
  }

  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List<VoidCallback>.from(_listeners)) {
      listener();
    }
  }

  /// Adapters that currently have usable credentials, in order.
  ///
  /// Skipping unconfigured ones here is what keeps a user with no AVDb key from
  /// seeing a failed request on every single metadata lookup.
  Future<List<MetadataProviderAdapter>> configured() async {
    final result = <MetadataProviderAdapter>[];
    for (final adapter in _adapters) {
      try {
        if (await adapter.isConfigured()) result.add(adapter);
      } catch (_) {
        // A misbehaving adapter must not block the others.
      }
    }
    return result;
  }
}