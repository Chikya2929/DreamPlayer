import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/video_item.dart';

/// How a media source can reach a Cast receiver.
///
/// The receiver **decodes the media itself**, so it has to be able to *fetch*
/// the URL. That is the whole difference between "plays on the phone" and
/// "plays on the TV", and it is why a local file is not castable out of the
/// box.
enum CastReach {
  /// The receiver can fetch this URL as it is.
  direct,

  /// The media is reachable from the phone only. It can be cast once the
  /// phone serves it over the LAN (the local media server).
  needsLocalServer,

  /// There is no way to hand this over to a receiver.
  unreachable,
}

/// The state of the Cast session, as reported by the native side.
class CastState {
  const CastState({
    this.available = false,
    this.connected = false,
    this.deviceName,
    this.positionMs = 0,
    this.playing = false,
    this.mediaLoaded = false,
  });

  /// Google Play services are present and the Cast SDK initialised.
  final bool available;

  /// A receiver is connected.
  final bool connected;

  /// The friendly name of the connected receiver.
  final String? deviceName;

  /// The receiver's playhead.
  final int positionMs;

  /// The receiver is playing.
  final bool playing;

  /// The receiver has media loaded.
  final bool mediaLoaded;

  static const CastState unknown = CastState();

  factory CastState.fromMap(Map<Object?, Object?> map) {
    return CastState(
      available: map['available'] == true,
      connected: map['connected'] == true,
      deviceName: map['deviceName'] as String?,
      positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
      playing: map['playing'] == true,
      mediaLoaded: map['mediaLoaded'] == true,
    );
  }
}

/// Thrown when a cast attempt cannot be made.
class CastException implements Exception {
  const CastException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'CastException($code): $message';
}

/// The Cast bridge.
///
/// The native side ([`CastManager.kt`](../android/app/src/main/kotlin/com/dreamplayer/app/CastManager.kt))
/// owns the route picker, the session and the remote media client; this is
/// the Dart half, plus the pure [castReachFor] rule that decides what can be
/// offered at all.
class CastManager extends ChangeNotifier {
  CastManager._();

  static final CastManager instance = CastManager._();

  static const MethodChannel _method = MethodChannel('dreamplayer/cast');
  static const EventChannel _events = EventChannel('dreamplayer/cast_events');

  StreamSubscription<Object?>? _subscription;
  CastState _state = CastState.unknown;

  /// The last known session state.
  CastState get state => _state;

  /// True when the Cast SDK is usable on this device.
  bool get isAvailable => _state.available;

  /// True when a receiver is connected.
  bool get isConnected => _state.connected;

  /// Subscribes to the native state stream. Safe to call more than once.
  void start() {
    _subscription ??= _events.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          _state = CastState.fromMap(event);
          notifyListeners();
        }
      },
      onError: (Object error) {
        debugPrint('cast events failed: $error');
      },
    );
    unawaited(refresh());
  }

  /// Reads the state once (used at startup, before the stream is ready).
  Future<void> refresh() async {
    try {
      final map = await _method.invokeMapMethod<Object?, Object?>('getState');
      if (map != null) {
        _state = CastState.fromMap(map);
        notifyListeners();
      }
    } on MissingPluginException {
      // Not Android, or the SDK never initialised — Cast is simply absent.
    } catch (error) {
      debugPrint('cast state failed: $error');
    }
  }

  /// Sends the media to the connected receiver.
  Future<void> cast({
    required String url,
    required String title,
    int positionMs = 0,
    String? contentType,
    String? imageUrl,
  }) async {
    try {
      await _method.invokeMethod<bool>('cast', <String, dynamic>{
        'url': url,
        'title': title,
        'positionMs': positionMs,
        'contentType': contentType,
        'imageUrl': imageUrl,
      });
    } on PlatformException catch (error) {
      throw CastException(error.code, error.message ?? 'The receiver refused the media');
    } on MissingPluginException {
      throw const CastException('unavailable', 'Casting is not available on this device');
    }
  }

  /// Stops the remote playback and ends the session.
  Future<void> stop() async {
    try {
      await _method.invokeMethod<bool>('stop');
    } on MissingPluginException {
      // Nothing to stop.
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}

/// Whether the host of [url] is the phone itself.
///
/// A loopback URL is meaningless to a receiver in another room, so it has to
/// be served over the LAN instead.
bool isLoopbackUrl(String url) {
  final Uri? parsed = Uri.tryParse(url);
  final String host = (parsed?.host ?? '').toLowerCase();
  return host == '127.0.0.1' || host == 'localhost' || host == '::1';
}

/// The URL a receiver would fetch for [video], if any.
///
/// Pure, so the rule can be unit-tested without a device:
///
/// * an `http(s)` URL with no authentication headers is fetched by the
///   receiver itself — castable as it is;
/// * a loopback URL (our own SMB proxy) or a source that needs request
///   headers (WebDAV basic auth) is only reachable through the phone, so it
///   needs the local media server;
/// * a file path, a `content://` URI, `smb://` or `ftp://` is likewise
///   phone-only.
CastReach castReachFor(VideoItem video) {
  final String uri = video.uri ?? '';
  final bool hasHeaders = video.httpHeaders.isNotEmpty;
  if (uri.startsWith('http://') || uri.startsWith('https://')) {
    if (hasHeaders) return CastReach.needsLocalServer;
    if (isLoopbackUrl(uri)) return CastReach.needsLocalServer;
    return CastReach.direct;
  }
  // No usable URL: a local path, a content:// URI, smb:// or ftp://.
  if (uri.isEmpty && video.path != null) return CastReach.needsLocalServer;
  return CastReach.unreachable;
}

/// The URL to hand to a receiver, when there is one.
///
/// `null` means "the receiver cannot fetch this as it is"; the caller then
/// decides whether to fall back to the local media server.
String? castableUrlFor(VideoItem video) {
  if (castReachFor(video) != CastReach.direct) return null;
  return video.uri;
}
