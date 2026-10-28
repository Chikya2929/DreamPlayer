import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// A DreamPlayer receiver (another DreamPlayer install on the LAN, e.g.
/// DreamPlayer on a Fire TV Stick) that can be sent a video to play.
class DreamCastTarget {
  const DreamCastTarget({
    required this.name,
    required this.address,
    required this.port,
  });

  final String name;
  final String address;

  /// The receiver's HTTP "play" port.
  final int port;
}

/// Discovery + send for the DreamCast receiver protocol (see
/// `DreamCast.kt`): a UDP broadcast finds receivers on port 51717 and each
/// accepts a direct `POST /play/<token>` with the resolved stream URL.
class DreamCastClient {
  static const _methodChannel = MethodChannel('dreamplayer/multicast');
  static const _receiverChannel = MethodChannel('dreamplayer/dreamcast');

  /// Asks whether this device should offer itself as a receiver (TVs).
  static Future<bool> isReceiverDevice() async {
    try {
      return await _receiverChannel.invokeMethod<bool>('isReceiverSupported') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Enables/disables the receiver foreground service on this device.
  static Future<void> setReceiverEnabled(bool enabled) async {
    try {
      await _receiverChannel.invokeMethod<void>(enabled ? 'enable' : 'disable');
    } on PlatformException {
      // The receiver is best-effort; playback is unaffected.
    }
  }

  /// Finds every DreamPlayer receiver on the LAN.
  Future<List<DreamCastTarget>> discover([Duration timeout = const Duration(seconds: 2)]) async {
    try {
      final raw = await _methodChannel.invokeMethod<List<dynamic>>(
        'discoverDreamCast',
        {'timeoutMs': timeout.inMilliseconds},
      );
      final targets = <DreamCastTarget>[];
      for (final item in raw ?? []) {
        if (item is! Map) continue;
        final address = item['address'] as String?;
        final port = item['port'] as int?;
        if (address == null || port == null) continue;
        targets.add(DreamCastTarget(
          name: (item['name'] as String?)?.isNotEmpty == true
              ? item['name'] as String
              : 'DreamPlayer ($address)',
          address: address,
          port: port,
        ));
      }
      return targets;
    } on PlatformException {
      return [];
    }
  }

  /// Pushes playback to [target]; the receiver opens the URL itself.
  Future<bool> send(
    DreamCastTarget target, {
    required String uri,
    required String title,
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client
          .postUrl(Uri.parse('http://${target.address}:${target.port}/play'));
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode('{"uri":${jsonEncode(uri)},"title":${jsonEncode(title)}}'));
      final response = await request.close();
      await response.drain<void>();
      final ok = response.statusCode == 200;
      client.close(force: true);
      return ok;
    } catch (_) {
      return false;
    }
  }
}
