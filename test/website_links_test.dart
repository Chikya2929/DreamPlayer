import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins the casing of the app website URL.
///
/// GitHub Pages serves this project at `mangeshghodke.github.io/DreamPlayer/`,
/// where the path IS the repository name, and GitHub matches it
/// **case-sensitively**. Measured against the live site:
///
///   /DreamPlayer/  -> 200
///   /DreamPlayer   -> 301 (GitHub adds the trailing slash)
///   /dreamplayer/  -> 404
///   /Dreamplayer/  -> 404
///
/// This is the OPPOSITE of the repo URL, which GitHub resolves
/// case-insensitively (`github.com/mangeshghodke/dreamplayer` works), so a
/// Pages link can look correct in the repo view and still 404 on the site.
///
/// Renaming the repo would only flip which casing works, and `/DreamPlayer/` is
/// already referenced from the README, the in-app Terms/Privacy buttons, the
/// App Review reply and the App Store listing — so the casing is pinned by
/// convention rather than fixed. A mistyped link fails as a silent 404, and the
/// Terms/Privacy links are App Review critical, so this is a test rather than a
/// convention.
///
/// Two things must NOT be flagged, and both are real occurrences in the repo:
///   * `img.shields.io/badge/Website-mangeshghodke.github.io-2D8CF0` — a badge
///     image whose HOSTNAME merely contains the string; not a site link.
///   * `mangeshghodke.github.io/DreamPlayer` as bare link TEXT — not a URL.
void main() {
  const host = 'mangeshghodke.github.io';
  const segment = 'DreamPlayer';

  List<File> sources() => [
        ...Directory('lib').listSync(recursive: true).whereType<File>(),
        ...Directory('docs').listSync(recursive: true).whereType<File>(),
        ...Directory('.github').listSync(recursive: true).whereType<File>(),
        ...['README.md', 'AGENTS.md', 'CHANGELOG.md'].map(File.new),
      ]
          .where((f) => f.path.endsWith('.dart') || f.path.endsWith('.md'))
          .toList();

  test('every Pages link uses the exact DreamPlayer casing', () {
    final offenders = <String>[];
    for (final file in sources()) {
      final content = file.readAsStringSync();
      var i = content.indexOf(host);
      while (i != -1) {
        final rest = content.substring(i + host.length);
        // Only a site reference if the host is followed by a path separator.
        // Read the first path segment as a URL token. Scanning to "next slash
        // or end of file" is wrong: a link target ends in `)`, e.g.
        // `.../DreamPlayer/)]`, which would swallow the rest of the document.
        final seg = RegExp(r'^/([A-Za-z0-9._-]+)').firstMatch(rest)?.group(1);
        if (seg != null) {
          if (seg != segment) {
            offenders.add('${file.path}: .../$seg/  (expected /$segment/)');
          }
        }
        i = content.indexOf(host, i + 1);
      }
    }
    expect(offenders, isEmpty,
        reason: 'lowercase or mixed-case Pages paths return 404. '
            'Expected the first path segment to be exactly "$segment".');
  });

  test('the shipped Terms and Privacy URLs keep the correct casing', () {
    const legal = {
      'https://mangeshghodke.github.io/DreamPlayer/terms': 'Terms of Use',
      'https://mangeshghodke.github.io/DreamPlayer/privacy': 'Privacy Policy',
    };
    for (final url in legal.keys) {
      expect(url, contains('https://$host/$segment/'), reason: url);
    }
  });
}
