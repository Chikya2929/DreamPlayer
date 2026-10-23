import 'package:dream_player/utils/ttf_names.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Uint8List> asset(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  group('ttfNameTableNames', () {
    test('reads the family and PostScript names the OS needs', () async {
      final poppins = ttfNameTableNames(
        await asset('assets/fonts/Poppins-Regular.ttf'),
      );
      // UIFont(name:) / Typeface accept the PostScript name; the family is
      // what the settings preview shows. Both must be recoverable.
      expect(poppins, contains('Poppins'));
      expect(poppins, contains('Poppins-Regular'));

      final openSans = ttfNameTableNames(
        await asset('assets/fonts/Open Sans-Regular.ttf'),
      );
      expect(openSans, contains('Open Sans'));
      expect(openSans, contains('OpenSans-Regular'));

      for (final path in [
        'assets/fonts/Playfair Display-Regular.ttf',
        'assets/fonts/Fira Code-Regular.ttf',
        'assets/fonts/Merriweather-Regular.ttf',
        'assets/fonts/Pacifico-Regular.ttf',
      ]) {
        expect(ttfNameTableNames(await asset(path)), isNotEmpty, reason: path);
      }
    });

    test('malformed input is empty, never an exception', () {
      expect(ttfNameTableNames(Uint8List(0)), isEmpty);
      expect(ttfNameTableNames(Uint8List.fromList([0, 1, 2, 3])), isEmpty);
      expect(
        ttfNameTableNames(Uint8List.fromList(List<int>.filled(64, 0xFF))),
        isEmpty,
      );
      // Valid-looking header, table records pointing past EOF.
      final bytes = ByteData(28);
      bytes.setUint32(0, 0x00010000);
      bytes.setUint16(4, 1);
      bytes.setUint32(12, 0x6E616D65); // 'name'
      bytes.setUint32(20, 0xFFFFFF00);
      expect(ttfNameTableNames(bytes.buffer.asUint8List()), isEmpty);
    });
  });

  group('fontNameMatches', () {
    test('accepts a family with a style suffix', () {
      expect(fontNameMatches('Poppins Regular', 'Poppins'), isTrue);
      expect(fontNameMatches('Poppins-Regular', 'Poppins'), isTrue);
      expect(fontNameMatches('OpenSans-Bold', 'Open Sans'), isTrue);
      expect(fontNameMatches('Open Sans', 'Open Sans'), isTrue);
      expect(fontNameMatches('IM Fell English SC', 'IM Fell English SC'), isTrue);
    });

    test('rejects a different family that merely shares a prefix', () {
      // The copy is named after the REQUESTED family and reused forever, so a
      // prefix-only test would permanently pin Roboto to Roboto Mono's file.
      expect(fontNameMatches('Roboto Mono', 'Roboto'), isFalse);
      expect(fontNameMatches('Roboto Slab', 'Roboto'), isFalse);
      expect(fontNameMatches('Inter Tight', 'Inter'), isFalse);
      expect(fontNameMatches('Poppins', 'Poppins Extra'), isFalse);
      expect(fontNameMatches('', 'Poppins'), isFalse);
    });

    test('normalises case, spaces and punctuation', () {
      expect(normaliseFontName('Open  Sans'), 'opensans');
      expect(normaliseFontName('Fira-Code_Regular'), 'firacoderegular');
      expect(normaliseFontName(' '), '');
    });
  });
}
