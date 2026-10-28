import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/video_item.dart';

/// Google Cast session bridge for the player.
///
/// The native side ([`CastManager.kt`]) owns the session and the
/// RemoteMediaClient; this class surfaces the session state and the one
/// decision Flutter owns: what to load on the receiver when a session
/// starts.
///
/// The receiver fetches the media itself, so a source is only castable when
/// it is a URL the receiver can reach. A `file://`/`content://` path, an
/// `smb://`/`ftp://` URI, a `127.0.0.1` loopback proxy (CX/SMB/MPV bridge)
/// or a URL that needs per-request headers (WebDAV/Jellyfin auth) means
/// nothing to a device in the next room — the LAN media server (Step 4b)
/// is what will make those castable.
enum CastEligibility {
  /// A live http(s) URL the receiver can fetch directly.
  directPlayable,

  /// The URL lives on this device (loopback proxy or local file): it needs
  /// the sender-side LAN media server before it can be cast.
  needsLocalServer,

  /// Anything else — keep playing locally.
  unreachable,
}

CastEligibility castEligibility(VideoItem video) {
  final uri = video.uri ?? '';
  if (uri.isEmpty) return CastEligibility.unreachable;
  final scheme = uri.split(':').first.toLowerCase();
  if (scheme == 'http' || scheme == 'https') {
    final host = Uri.tryParse(uri)?.host ?? '';
    if (host.isEmpty) return CastEligibility.unreachable;
    final isLoopback = host == '127.0.0.1' || host == 'localhost' || host == '::1';
    if (isLoopback) return CastEligibility.needsLocalServer;
    if (video.httpHeaders.isNotEmpty) {
      return CastEligibility.unreachable;
    }
    return CastEligibility.directPlayable;
  }
  if (scheme == 'smb' || scheme == 'ftp' || scheme == 'ftps' || scheme == 'sftp') {
    return CastEligibility.needsLocalServer;
  }
  return CastEligibility.unreachable;
}

class CastManager extends ChangeNotifier {
  CastManager._();

  static final CastManager instance = CastManager._();

  static const _methodChannel = MethodChannel('dreamplayer/cast');
  static const _eventChannel = EventChannel('dreamplayer/cast_events');

  bool available = false;
  bool connected = false;
  String? deviceName;

  bool _listening = false;

  void ensureListening() {
    if (_listening) return;
    _listening = true;
    _eventChannel.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
    refreshState();
  }

  Future<void> refreshState() async {
    try {
      final map = await _methodChannel.invokeMethod<Map<String, dynamic>>('getState');
      if (map == null) return;
      available = map['available'] == true;
      connected = map['connected'] == true;
      deviceName = map['deviceName'] as String?;
      notifyListeners();
    } on PlatformException {
      // No Google Play services on the device.
      available = false;
      connected = false;
      notifyListeners();
    }
  }

  void _onEvent(dynamic event) {
    if (event is! Map || !event.containsKey('event')) return;
    connected = event['connected'] == true;
    deviceName = event['deviceName'] as String?;
    available = true;
    notifyListeners();
  }

  /// Opens the fullscreen expanded controller, if a session is live.
  Future<void> stopCasting() async {
    try {
      await _methodChannel.invokeMethod('stop');
    } on PlatformException {
      // ignored — nothing connected
    }
  }

  /// Pushes the current video to the receiver. Returns true when accepted.
  Future<bool> loadCurrent(
    VideoItem video, {
    required int positionMs,
    required String title,
  }) async {
    final uri = video.uri;
    if (uri == null || uri.isEmpty) return false;
    try {
      final result = await _methodChannel
          .invokeMethod<Map<String, dynamic>>('loadCurrent', <String, dynamic>{
        'url': uri,
        'mimeType': 'video/mp4',
        'title': title,
        'positionMs': positionMs,
      });
      return result?['ok'] == true;
    } on PlatformException {
      return false;
    }
  }
}
