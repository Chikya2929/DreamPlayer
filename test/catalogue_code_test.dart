import 'package:dream_player/services/metadata_provider_adapter.dart';
import 'package:dream_player/services/tmdb_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// The catalogue code is the only thing that identifies a JAV title, and the
/// PARSED title cannot carry it: the filename parser treats a trailing number
/// as a movie-part suffix, so `SVFLA-012.mkv` parses to the title "SVFLA"
/// (issue #52).
///
/// The adapters therefore read the code from the RAW name, which rides along
/// on [ParsedFileName.rawName].
void main() {
  group('catalogueCodeIn', () {
    test('a plain code is found', () {
      expect(
        MetadataProviderAdapter.catalogueCodeIn('SVFLA-012.mkv'),
        'SVFLA-012',
      );
    });

    test('the separator-less spelling is found', () {
      expect(
        MetadataProviderAdapter.catalogueCodeIn('SVFLA012.mkv'),
        'SVFLA-012',
      );
    });

    test('a code after a studio prefix is found', () {
      expect(
        MetadataProviderAdapter.catalogueCodeIn('[FLAVORY] SVFLA-012.mkv'),
        'SVFLA-012',
      );
    });

    test('a code at the front of a longer name is found', () {
      expect(
        MetadataProviderAdapter.catalogueCodeIn('SVFLA-012 Some Title 1080p.mkv'),
        'SVFLA-012',
      );
    });

    test('a lowercase code is normalised', () {
      expect(
        MetadataProviderAdapter.catalogueCodeIn('miaa-818.mkv'),
        'MIAA-818',
      );
    });

    test('a resolution is not a code', () {
      expect(
        MetadataProviderAdapter.catalogueCodeIn('HEVC-1080p.mkv'),
        isNull,
      );
    });

    test('a plain movie title has no code', () {
      expect(
        MetadataProviderAdapter.catalogueCodeIn('Dark.S01E01.mkv'),
        isNull,
      );
    });

    test('a title with a year has no code', () {
      expect(
        MetadataProviderAdapter.catalogueCodeIn('The Matrix 1999.mkv'),
        isNull,
      );
    });
  });

  group('the raw name survives parsing', () {
    test('the parsed title drops the code, the raw name keeps it', () {
      final parsed = ParsedFileName.parse('SVFLA-012.mkv');
      // The parser treats the trailing number as a movie-part suffix.
      expect(parsed.title, 'SVFLA');
      expect(parsed.rawName, 'SVFLA-012.mkv');
      expect(
        MetadataProviderAdapter.catalogueCodeIn(parsed.rawName!),
        'SVFLA-012',
      );
    });

    test('a regular episode keeps its raw name too', () {
      final parsed = ParsedFileName.parse('House.S02E04.mkv');
      expect(parsed.rawName, 'House.S02E04.mkv');
    });
  });
}
