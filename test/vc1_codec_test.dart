import 'package:flutter_test/flutter_test.dart';

import 'package:dream_player/utils/vc1_codec.dart';

/// Issue #51. VC-1 Advanced in Matroska produced a silent black screen on the
/// default engine: the platform advertises a VC-1 decoder, it initialises, and
/// it then outputs nothing without erroring, so the error-triggered software
/// fallback never fires.
void main() {
  group('isVc1Codec', () {
    test('matches the spellings containers actually report', () {
      // The reporter's file: Codec ID `V_MS/VFW/FOURCC / WVC1`.
      expect(isVc1Codec('wvc1'), isTrue);
      expect(isVc1Codec('WVC1'), isTrue);
      expect(isVc1Codec('vc1'), isTrue);
      expect(isVc1Codec('VC-1'), isTrue, reason: 'hyphenated spelling normalises');
      expect(isVc1Codec('video/vc1'), isTrue);
    });

    test('tolerates the profile suffix Media3 appends', () {
      expect(isVc1Codec('wvc1.Advanced.L3'), isTrue);
      expect(isVc1Codec('wvc1.Main'), isTrue);
    });

    test('does not fire on other codecs', () {
      expect(isVc1Codec('avc1.640028'), isFalse);
      expect(isVc1Codec('hev1.2.4.L153.B0'), isFalse);
      expect(isVc1Codec('hvc1'), isFalse);
      expect(isVc1Codec('video/avc'), isFalse);
      // "vc1" as a substring of something else must not match.
      expect(isVc1Codec('avc1'), isFalse);
    });

    test('handles absent values', () {
      expect(isVc1Codec(null), isFalse);
      expect(isVc1Codec(''), isFalse);
    });
  });

  group('isVc1AdvancedProfile', () {
    test('true only for the Advanced profile', () {
      expect(isVc1AdvancedProfile('wvc1.Advanced.L3'), isTrue);
      expect(isVc1AdvancedProfile('vc1.Advanced'), isTrue);
    });

    test('false for Simple and Main', () {
      // Simple/Main are what old hardware decoders can handle; warning on those
      // would push a working hardware path onto a slower one.
      expect(isVc1AdvancedProfile('wvc1.Simple'), isFalse);
      expect(isVc1AdvancedProfile('wvc1.Main'), isFalse);
      expect(isVc1AdvancedProfile('vc1.Main.L3'), isFalse);
    });

    test('false when there is no profile at all', () {
      // Absence of a profile is NOT evidence of Advanced -- reading it that way
      // would warn on every plain-VC-1 file.
      expect(isVc1AdvancedProfile('wvc1'), isFalse);
      expect(isVc1AdvancedProfile('vc1'), isFalse);
    });

    test('false for a non-VC-1 codec that happens to say advanced', () {
      expect(isVc1AdvancedProfile('avc1.Advanced'), isFalse);
    });
  });

  group('shouldWarnVc1', () {
    test('fires on any VC-1 signal, profile present or not', () {
      // Warning only on a confirmed Advanced profile would miss issue #51
      // whenever Media3 omits the profile string -- and Android has no
      // practical VC-1 hardware decoder for Simple/Main either, so the
      // suggestion costs nothing.
      expect(shouldWarnVc1(codecs: 'wvc1.Advanced.L3'), isTrue);
      expect(shouldWarnVc1(codecs: 'wvc1'), isTrue);
      expect(shouldWarnVc1(codecs: 'wvc1.Main'), isTrue);
      expect(shouldWarnVc1(mime: 'video/vc1'), isTrue);
      expect(shouldWarnVc1(codecs: null, mime: 'video/vc1'), isTrue);
    });

    test('stays quiet for everything that is not VC-1', () {
      expect(shouldWarnVc1(codecs: 'avc1.640028', mime: 'video/avc'), isFalse);
      expect(shouldWarnVc1(codecs: null, mime: null), isFalse);
      expect(shouldWarnVc1(codecs: 'hev1.2.4.L153.B0'), isFalse);
    });
  });
}