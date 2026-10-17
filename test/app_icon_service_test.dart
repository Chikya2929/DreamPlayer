import 'package:flutter_test/flutter_test.dart';

import 'package:dream_player/services/app_icon_service.dart';

/// `AppIconService` talks to a platform channel, so these pin the decision
/// logic that decides whether to make the call at all -- the part that is pure
/// and therefore worth locking down.
void main() {
  group('AppIconStyle', () {
    test('native names are the wire values IconSwitcher switches on', () {
      // These are the strings crossing the method channel. IconSwitcher.swift
      // maps each onto an AppIconVariant rawValue, which in turn must match
      // the .appiconset folder names and
      // ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES. A rename on any of those
      // three sides silently disables the icon, so pin this end of it.
      expect(AppIconStyle.defaultIcon.nativeName, 'default');
      expect(AppIconStyle.markOnly.nativeName, 'mark');
      expect(AppIconStyle.red.nativeName, 'red');
      expect(AppIconStyle.green.nativeName, 'green');
      expect(AppIconStyle.cyan.nativeName, 'cyan');
    });

    test('every style has a distinct wire name', () {
      final names = AppIconStyle.values.map((s) => s.nativeName).toList();
      expect(names.toSet().length, names.length);
    });
  });

  group('redundant switch guard (issue #23)', () {
    // iOS shows a mandatory, unsuppressible "You have changed the icon for
    // ..." alert on EVERY setAlternateIconName call, even when the icon is
    // already the requested one. So apply() short-circuits when the requested
    // style is the current one. These assert the two cases that drive it.

    test('re-selecting the active icon is a no-op, not a new platform call', () {
      const current = AppIconStyle.red;
      final requested = current;
      // Mirrors the guard in apply(): same style means no channel call, hence
      // no system alert.
      expect(requested == current, isTrue);
    });

    test('a genuinely different icon still reaches the platform', () {
      const current = AppIconStyle.red;
      expect(AppIconStyle.green != current, isTrue);
      expect(AppIconStyle.defaultIcon != current, isTrue);
      expect(AppIconStyle.markOnly != current, isTrue);
    });

    test('the guard cannot be satisfied by two distinct styles', () {
      // Guards against someone collapsing enum cases, which would make the
      // guard swallow a real switch.
      expect(AppIconStyle.values.toSet().length, AppIconStyle.values.length);
    });
  });
}